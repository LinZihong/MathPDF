#import "PDFPersistenceBridge.h"

#import <CommonCrypto/CommonDigest.h>

#include <qpdf/Constants.h>
#include <qpdf/QPDF.hh>
#include <qpdf/QPDFObjGen.hh>
#include <qpdf/QPDFObjectHandle.hh>
#include <qpdf/QPDFWriter.hh>

#include <map>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

NSString * const MPPDFPersistenceErrorDomain = @"MathPDF.PDFPersistence";

enum class ErrorCode: NSInteger {
    invalidSource = 1,
    unsupportedSource = 2,
    invalidRequest = 3,
    serializationFailed = 4,
};

NSError *makeError(ErrorCode code, NSString *message)
{
    return [NSError errorWithDomain:MPPDFPersistenceErrorDomain
                               code:static_cast<NSInteger>(code)
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString *stringFromUTF8(std::string const& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

NSString *warningSummary(QPDF& pdf)
{
    NSMutableArray<NSString *> *messages = [NSMutableArray array];
    for (auto const& warning: pdf.getWarnings()) {
        [messages addObject:stringFromUTF8(warning.what())];
    }
    return messages.count == 0 ? @"" : [messages componentsJoinedByString:@"; "];
}

NSString *nameWithoutSlash(QPDFObjectHandle object)
{
    if (!object.isName()) {
        return @"";
    }
    std::string name = object.getName();
    if (!name.empty() && name.front() == '/') {
        name.erase(name.begin());
    }
    return stringFromUTF8(name);
}

NSString *stringValue(QPDFObjectHandle object)
{
    if (!object.isString()) {
        return @"";
    }
    return stringFromUTF8(object.getUTF8Value());
}

NSNumber *integerValue(QPDFObjectHandle object, NSInteger fallback = 0)
{
    long long value = 0;
    if (!object.getValueAsInt(value)) {
        value = fallback;
    }
    return @(value);
}

NSDictionary *referenceDictionary(QPDFObjectHandle object)
{
    QPDFObjGen reference = object.getObjGen();
    if (!reference.isIndirect()) {
        return @{};
    }
    return @{
        @"object": @(reference.getObj()),
        @"generation": @(reference.getGen()),
    };
}

bool isSignatureDictionary(QPDFObjectHandle object)
{
    if (!object.isDictionary()) {
        return false;
    }
    if (object.getKey("/Type").isOrHasName("/Sig") ||
        object.getKey("/FT").isOrHasName("/Sig")) {
        return true;
    }
    auto byteRange = object.getKey("/ByteRange");
    return byteRange.isArray() && byteRange.getArrayNItems() >= 4 &&
           object.hasKey("/Contents");
}

bool hasReachableSignature(QPDF& pdf)
{
    auto root = pdf.getRoot();
    if (root.hasKey("/Perms")) {
        return true;
    }

    for (auto const& entry: pdf.getXRefTable()) {
        if (isSignatureDictionary(pdf.getObject(entry.first))) {
            return true;
        }
    }
    return false;
}

struct AnnotationNode {
    int pageIndex;
    int slot;
    QPDFObjectHandle object;
    QPDFObjGen reference;
    std::string subtype;
    QPDFObjGen popup;
    QPDFObjGen parent;
};

NSString *fingerprint(AnnotationNode const& node)
{
    auto rect = node.object.getKey("/Rect");
    auto contents = node.object.getKey("/Contents");
    auto name = node.object.getKey("/NM");
    std::string value = node.subtype + "|" + rect.unparse() + "|" +
                        contents.unparse() + "|" + name.unparse();
    return stringFromUTF8(value);
}

NSDictionary *annotationDictionary(AnnotationNode const& node)
{
    NSMutableDictionary *result = [@{
        @"slot": @(node.slot),
        @"object": @(node.reference.getObj()),
        @"generation": @(node.reference.getGen()),
        @"subtype": stringFromUTF8(node.subtype),
        @"nm": stringValue(node.object.getKey("/NM")),
        @"fingerprint": fingerprint(node),
        @"flags": integerValue(node.object.getKey("/F")),
        @"open": node.object.getKey("/Open").isBool()
            ? @(node.object.getKey("/Open").getBoolValue())
            : @NO,
        @"hasAppearance": @(node.object.hasKey("/AP")),
    } mutableCopy];
    if (node.popup.isIndirect()) {
        result[@"popup"] = @{
            @"object": @(node.popup.getObj()),
            @"generation": @(node.popup.getGen()),
        };
    }
    if (node.parent.isIndirect()) {
        result[@"parent"] = @{
            @"object": @(node.parent.getObj()),
            @"generation": @(node.parent.getGen()),
        };
    }
    return result;
}

struct InventoryResult {
    NSMutableArray *pages;
    bool graphSupported;
    NSString *graphFailure;
};

InventoryResult inventoryAnnotations(QPDF& pdf, bool requireReciprocal = false)
{
    NSMutableArray *pagesJSON = [NSMutableArray array];
    std::vector<AnnotationNode> nodes;
    std::map<QPDFObjGen, size_t> nodeByReference;
    std::map<std::string, QPDFObjGen> referenceByName;
    bool supported = true;
    NSString *failure = @"";

    auto const& pages = pdf.getAllPages();
    for (size_t pageIndex = 0; pageIndex < pages.size(); ++pageIndex) {
        auto page = pages.at(pageIndex);
        NSMutableArray *annotationsJSON = [NSMutableArray array];
        auto annots = page.getKey("/Annots");
        if (!annots.isNull() && !annots.isArray()) {
            supported = false;
            failure = @"A page has a non-array /Annots entry.";
        } else if (annots.isArray()) {
            for (int slot = 0; slot < annots.getArrayNItems(); ++slot) {
                auto annotation = annots.getArrayItem(slot);
                if (!annotation.isDictionary()) {
                    supported = false;
                    failure = @"A page annotation is not a dictionary.";
                    continue;
                }
                auto reference = annotation.getObjGen();
                if (!reference.isIndirect()) {
                    supported = false;
                    failure = @"Direct annotation dictionaries are not editable yet.";
                }
                auto subtypeObject = annotation.getKey("/Subtype");
                std::string subtype = subtypeObject.isName() ? subtypeObject.getName() : "";
                if (!subtype.empty() && subtype.front() == '/') {
                    subtype.erase(subtype.begin());
                }
                AnnotationNode node{
                    static_cast<int>(pageIndex),
                    slot,
                    annotation,
                    reference,
                    subtype,
                    annotation.getKey("/Popup").getObjGen(),
                    annotation.getKey("/Parent").getObjGen(),
                };
                size_t index = nodes.size();
                nodes.push_back(node);
                if (reference.isIndirect()) {
                    if (!nodeByReference.emplace(reference, index).second) {
                        supported = false;
                        failure = @"An annotation object is shared by multiple page entries.";
                    }
                }
                auto name = annotation.getKey("/NM");
                if (name.isString() && !name.getUTF8Value().empty()) {
                    if (!referenceByName.emplace(name.getUTF8Value(), reference).second) {
                        supported = false;
                        failure = @"Annotation /NM identifiers are not unique.";
                    }
                }
                [annotationsJSON addObject:annotationDictionary(node)];
            }
        }

        QPDFObjGen pageReference = page.getObjGen();
        [pagesJSON addObject:@{
            @"index": @(pageIndex),
            @"object": @(pageReference.getObj()),
            @"generation": @(pageReference.getGen()),
            @"annotations": annotationsJSON,
        }];
    }

    std::map<QPDFObjGen, int> popupInboundCount;
    for (auto const& node: nodes) {
        if (node.popup.isIndirect()) {
            ++popupInboundCount[node.popup];
            auto popup = nodeByReference.find(node.popup);
            if (popup == nodeByReference.end() || nodes[popup->second].subtype != "Popup") {
                supported = false;
                failure = @"An annotation /Popup edge does not target a page Popup annotation.";
                continue;
            }
            auto const& popupNode = nodes[popup->second];
            if (popupNode.pageIndex != node.pageIndex) {
                supported = false;
                failure = @"A Popup edge crosses page boundaries.";
            }
            if (!popupNode.parent.isIndirect() && requireReciprocal) {
                supported = false;
                failure = @"A written Popup is missing its reciprocal /Parent edge.";
            } else if (popupNode.parent.isIndirect() && popupNode.parent != node.reference) {
                supported = false;
                failure = @"A Popup /Parent conflicts with its owner's /Popup edge.";
            }
        }
    }

    for (auto const& node: nodes) {
        if (node.subtype != "Popup") {
            continue;
        }
        int inbound = popupInboundCount[node.reference];
        if (inbound > 1) {
            supported = false;
            failure = @"A Popup annotation has multiple owners.";
        }
        if (node.parent.isIndirect()) {
            auto parent = nodeByReference.find(node.parent);
            if (parent == nodeByReference.end() || nodes[parent->second].subtype == "Popup") {
                supported = false;
                failure = @"A Popup /Parent does not target an owning page annotation.";
                continue;
            }
            auto const& owner = nodes[parent->second];
            if (owner.pageIndex != node.pageIndex) {
                supported = false;
                failure = @"A Popup /Parent crosses page boundaries.";
            }
            if (!owner.popup.isIndirect() && requireReciprocal) {
                supported = false;
                failure = @"A written owner is missing its reciprocal /Popup edge.";
            } else if (owner.popup.isIndirect() && owner.popup != node.reference) {
                supported = false;
                failure = @"An owner's /Popup edge conflicts with the Popup /Parent.";
            }
        } else if (inbound == 0) {
            supported = false;
            failure = @"An orphan Popup annotation has no explicit relationship.";
        } else if (requireReciprocal) {
            supported = false;
            failure = @"A written Popup is missing its reciprocal /Parent edge.";
        }
    }

    return {pagesJSON, supported, failure};
}

NSData *jsonData(id object, NSError **error)
{
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:error];
}

NSString *sha256Hex(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, static_cast<CC_LONG>(data.length), digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

NSArray *arrayValue(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

NSDictionary *dictionaryValue(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

NSString *requiredString(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    if (![value isKindOfClass:NSString.class]) {
        throw std::runtime_error("Missing string field " + std::string(key.UTF8String));
    }
    return value;
}

NSNumber *requiredNumber(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    if (![value isKindOfClass:NSNumber.class]) {
        throw std::runtime_error("Missing numeric field " + std::string(key.UTF8String));
    }
    return value;
}

std::string utf8(NSString *value)
{
    return value == nil ? std::string() : std::string(value.UTF8String ?: "");
}

QPDFObjectHandle numberArray(NSArray *values)
{
    std::vector<QPDFObjectHandle> objects;
    objects.reserve(values.count);
    for (id value in values) {
        if (![value isKindOfClass:NSNumber.class]) {
            throw std::runtime_error("A PDF numeric array contains a non-number.");
        }
        objects.push_back(QPDFObjectHandle::newReal([value doubleValue], 6));
    }
    return QPDFObjectHandle::newArray(objects);
}

std::set<std::string> dirtyFields(NSDictionary *record)
{
    std::set<std::string> result;
    for (id value in arrayValue(record, @"dirty")) {
        if ([value isKindOfClass:NSString.class]) {
            result.insert(utf8(value));
        }
    }
    return result;
}

std::string pdfDate(NSNumber *seconds)
{
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"'D:'yyyyMMddHHmmss'Z'";
    return utf8([formatter stringFromDate:date]);
}

QPDFObjectHandle resolveOrigin(
    QPDF& pdf,
    std::vector<QPDFObjectHandle> const& pages,
    NSDictionary *origin
)
{
    int pageIndex = requiredNumber(origin, @"pageIndex").intValue;
    int pageObject = requiredNumber(origin, @"pageObject").intValue;
    int pageGeneration = requiredNumber(origin, @"pageGeneration").intValue;
    int slot = requiredNumber(origin, @"slot").intValue;
    int object = requiredNumber(origin, @"object").intValue;
    int generation = requiredNumber(origin, @"generation").intValue;
    if (pageIndex < 0 || static_cast<size_t>(pageIndex) >= pages.size()) {
        throw std::runtime_error("An annotation origin names an invalid page.");
    }
    auto page = pages.at(static_cast<size_t>(pageIndex));
    if (page.getObjGen() != QPDFObjGen(pageObject, pageGeneration)) {
        throw std::runtime_error("The source page identity changed.");
    }
    auto annots = page.getKey("/Annots");
    if (!annots.isArray() || slot < 0 || slot >= annots.getArrayNItems()) {
        throw std::runtime_error("The source annotation slot changed.");
    }
    auto annotation = annots.getArrayItem(slot);
    if (annotation.getObjGen() != QPDFObjGen(object, generation)) {
        throw std::runtime_error("The source annotation object identity changed.");
    }
    std::string subtype = utf8(requiredString(origin, @"subtype"));
    AnnotationNode node{
        pageIndex,
        slot,
        annotation,
        annotation.getObjGen(),
        subtype,
        annotation.getKey("/Popup").getObjGen(),
        annotation.getKey("/Parent").getObjGen(),
    };
    if (![fingerprint(node) isEqualToString:requiredString(origin, @"fingerprint")]) {
        throw std::runtime_error("The source annotation fingerprint changed.");
    }
    return annotation;
}

void replaceOptionalString(
    QPDFObjectHandle object,
    std::string const& key,
    NSDictionary *record,
    NSString *jsonKey,
    bool unicode = true
)
{
    id value = record[jsonKey];
    if ([value isKindOfClass:NSString.class]) {
        object.replaceKey(
            key,
            unicode
                ? QPDFObjectHandle::newUnicodeString(utf8(value))
                : QPDFObjectHandle::newString(utf8(value))
        );
    } else {
        object.removeKey(key);
    }
}

void applyRecord(QPDFObjectHandle object, NSDictionary *record, bool created)
{
    std::set<std::string> dirty = dirtyFields(record);
    auto changes = [&](std::string const& key) {
        return created || dirty.contains(key);
    };

    if (created) {
        object.replaceKey("/Type", QPDFObjectHandle::newName("/Annot"));
        object.replaceKey(
            "/Subtype",
            QPDFObjectHandle::newName("/" + utf8(requiredString(record, @"subtype")))
        );
    }
    if (changes("Rect")) {
        object.replaceKey("/Rect", numberArray(arrayValue(record, @"rectangle")));
    }
    if (changes("QuadPoints")) {
        NSArray *values = arrayValue(record, @"quadrilateralPoints");
        if (values.count > 0) {
            object.replaceKey("/QuadPoints", numberArray(values));
        } else {
            object.removeKey("/QuadPoints");
        }
    }
    if (changes("Contents")) {
        replaceOptionalString(object, "/Contents", record, @"contents");
    }
    if (changes("RC")) {
        object.removeKey("/RC");
    }
    if (changes("M")) {
        id seconds = record[@"modificationDate"];
        if ([seconds isKindOfClass:NSNumber.class]) {
            object.replaceKey("/M", QPDFObjectHandle::newString(pdfDate(seconds)));
        } else {
            object.removeKey("/M");
        }
    }
    if (changes("C")) {
        object.replaceKey("/C", numberArray(arrayValue(record, @"color")));
    }
    if (changes("F")) {
        object.replaceKey(
            "/F",
            QPDFObjectHandle::newInteger(requiredNumber(record, @"flags").longLongValue)
        );
    }
    if (changes("Open")) {
        object.replaceKey(
            "/Open",
            QPDFObjectHandle::newBool(requiredNumber(record, @"open").boolValue)
        );
    }
    if (changes("NM")) {
        object.replaceKey(
            "/NM",
            QPDFObjectHandle::newUnicodeString(utf8(requiredString(record, @"name")))
        );
    }
    if (changes("Name")) {
        id iconName = record[@"iconName"];
        if ([iconName isKindOfClass:NSString.class] && [iconName length] > 0) {
            object.replaceKey(
                "/Name",
                QPDFObjectHandle::newName("/" + utf8(iconName))
            );
        } else {
            object.removeKey("/Name");
        }
    }
    if (changes("T")) {
        replaceOptionalString(object, "/T", record, @"userName");
    }
    if (changes("Subj")) {
        replaceOptionalString(object, "/Subj", record, @"subject");
    }
}

void patchKeywords(QPDF& pdf, NSString *preamble)
{
    auto trailer = pdf.getTrailer();
    auto info = trailer.getKey("/Info");
    if (!info.isDictionary()) {
        info = pdf.makeIndirectObject(QPDFObjectHandle::newDictionary());
        trailer.replaceKey("/Info", info);
    }

    std::string markerPrefix = "MathPDF-Preamble-v1:";
    std::string marker;
    if (preamble.length > 0) {
        NSData *data = [preamble dataUsingEncoding:NSUTF8StringEncoding];
        marker = markerPrefix + utf8([data base64EncodedStringWithOptions:0]);
    }

    auto keywords = info.getKey("/Keywords");
    if (keywords.isArray()) {
        std::vector<QPDFObjectHandle> retained;
        for (auto item: keywords.getArrayAsVector()) {
            std::string value;
            if (item.isString()) {
                value = item.getUTF8Value();
            }
            if (!value.starts_with(markerPrefix)) {
                retained.push_back(item);
            }
        }
        if (!marker.empty()) {
            retained.push_back(QPDFObjectHandle::newUnicodeString(marker));
        }
        keywords.setArrayFromVector(retained);
        return;
    }

    std::string value = keywords.isString() ? keywords.getUTF8Value() : std::string();
    std::regex markerPattern("MathPDF-Preamble-v1:[A-Za-z0-9+/=]+");
    value = std::regex_replace(value, markerPattern, "");
    while (!value.empty() &&
           (value.back() == ' ' || value.back() == ',' || value.back() == ';')) {
        value.pop_back();
    }
    if (!marker.empty()) {
        if (!value.empty()) {
            value += ", ";
        }
        value += marker;
    }
    if (value.empty()) {
        info.removeKey("/Keywords");
    } else {
        info.replaceKey("/Keywords", QPDFObjectHandle::newUnicodeString(value));
    }
}

NSData *serializeGraph(NSData *sourceData, NSDictionary *request)
{
    if (![sha256Hex(sourceData) isEqualToString:requiredString(request, @"sourceSHA256")]) {
        throw std::runtime_error("The persistence request does not match its source PDF.");
    }

    QPDF pdf;
    pdf.setAttemptRecovery(false);
    pdf.setSuppressWarnings(true);
    pdf.processMemoryFile(
        "MathPDF source",
        static_cast<char const *>(sourceData.bytes),
        sourceData.length
    );
    if (pdf.isEncrypted()) {
        throw std::runtime_error("Encrypted PDFs are read-only.");
    }
    if (hasReachableSignature(pdf)) {
        throw std::runtime_error("Signed PDFs are read-only.");
    }
    auto inventory = inventoryAnnotations(pdf);
    if (pdf.anyWarnings()) {
        throw std::runtime_error(
            "qpdf reported warnings while reading the source PDF: " +
            utf8(warningSummary(pdf))
        );
    }
    if (!inventory.graphSupported) {
        throw std::runtime_error(utf8(inventory.graphFailure));
    }

    auto const& pages = pdf.getAllPages();
    NSMutableDictionary<NSString *, NSDictionary *> *recordByID = [NSMutableDictionary dictionary];
    std::map<std::string, QPDFObjectHandle> objectByID;
    std::map<int, std::vector<QPDFObjectHandle>> createdByPage;
    std::set<QPDFObjGen> deletedReferences;

    for (id value in arrayValue(request, @"annotations")) {
        if (![value isKindOfClass:NSDictionary.class]) {
            throw std::runtime_error("The annotation request contains a non-dictionary record.");
        }
        NSDictionary *record = value;
        NSString *identifier = requiredString(record, @"id");
        recordByID[identifier] = record;
        NSDictionary *origin = dictionaryValue(record, @"origin");
        bool deleted = requiredNumber(record, @"deleted").boolValue;

        if (origin != nil) {
            auto object = resolveOrigin(pdf, pages, origin);
            objectByID.emplace(utf8(identifier), object);
            if (deleted) {
                deletedReferences.insert(object.getObjGen());
            } else {
                applyRecord(object, record, false);
            }
        } else if (!deleted) {
            int pageIndex = requiredNumber(record, @"pageIndex").intValue;
            if (pageIndex < 0 || static_cast<size_t>(pageIndex) >= pages.size()) {
                throw std::runtime_error("A new annotation names an invalid page.");
            }
            auto object = pdf.makeIndirectObject(QPDFObjectHandle::newDictionary());
            applyRecord(object, record, true);
            objectByID.emplace(utf8(identifier), object);
            createdByPage[pageIndex].push_back(object);
        }
    }

    std::map<std::string, std::string> popupByOwner;
    std::map<std::string, std::string> ownerByPopup;
    for (id value in arrayValue(request, @"edges")) {
        if (![value isKindOfClass:NSDictionary.class]) {
            throw std::runtime_error("The popup edge request contains a non-dictionary record.");
        }
        NSDictionary *edge = value;
        std::string owner = utf8(requiredString(edge, @"owner"));
        std::string popup = utf8(requiredString(edge, @"popup"));
        if (!objectByID.contains(owner) || !objectByID.contains(popup)) {
            throw std::runtime_error("A popup edge refers to a missing annotation.");
        }
        if (!popupByOwner.emplace(owner, popup).second ||
            !ownerByPopup.emplace(popup, owner).second) {
            throw std::runtime_error("Popup edges are not one-to-one.");
        }
    }

    for (auto& item: objectByID) {
        NSString *identifier = stringFromUTF8(item.first);
        NSDictionary *record = recordByID[identifier];
        if (record == nil || requiredNumber(record, @"deleted").boolValue) {
            continue;
        }
        bool created = dictionaryValue(record, @"origin") == nil;
        auto dirty = dirtyFields(record);
        if (created || dirty.contains("Popup")) {
            auto edge = popupByOwner.find(item.first);
            if (edge == popupByOwner.end()) {
                item.second.removeKey("/Popup");
            } else {
                item.second.replaceKey("/Popup", objectByID.at(edge->second));
            }
        }
        if (created || dirty.contains("Parent")) {
            auto edge = ownerByPopup.find(item.first);
            if (edge == ownerByPopup.end()) {
                item.second.removeKey("/Parent");
            } else {
                item.second.replaceKey("/Parent", objectByID.at(edge->second));
            }
        }
    }

    for (size_t pageIndex = 0; pageIndex < pages.size(); ++pageIndex) {
        auto page = pages.at(pageIndex);
        auto annots = page.getKey("/Annots");
        std::vector<QPDFObjectHandle> retained;
        if (annots.isArray()) {
            for (auto item: annots.getArrayAsVector()) {
                if (!deletedReferences.contains(item.getObjGen())) {
                    retained.push_back(item);
                }
            }
        }
        auto additions = createdByPage.find(static_cast<int>(pageIndex));
        if (additions != createdByPage.end()) {
            retained.insert(retained.end(), additions->second.begin(), additions->second.end());
        }
        if (!annots.isArray()) {
            if (!retained.empty()) {
                page.replaceKey("/Annots", QPDFObjectHandle::newArray(retained));
            }
        } else {
            annots.setArrayFromVector(retained);
        }
    }

    NSDictionary *metadata = dictionaryValue(request, @"metadata");
    if (metadata != nil && requiredNumber(metadata, @"dirty").boolValue) {
        patchKeywords(pdf, requiredString(metadata, @"preamble"));
    }

    QPDFWriter writer(pdf);
    writer.setOutputMemory();
    writer.setObjectStreamMode(qpdf_o_preserve);
    writer.setStreamDataMode(qpdf_s_preserve);
    writer.setPreserveUnreferencedObjects(true);
    writer.write();
    if (pdf.anyWarnings()) {
        throw std::runtime_error(
            "qpdf reported warnings while writing the PDF: " +
            utf8(warningSummary(pdf))
        );
    }
    auto buffer = writer.getBufferSharedPointer();
    NSData *result = [NSData dataWithBytes:buffer->getBuffer() length:buffer->getSize()];

    QPDF verification;
    verification.setAttemptRecovery(false);
    verification.setSuppressWarnings(true);
    verification.processMemoryFile(
        "MathPDF output",
        static_cast<char const *>(result.bytes),
        result.length
    );
    auto verifiedInventory = inventoryAnnotations(verification, true);
    if (verification.anyWarnings()) {
        throw std::runtime_error(
            "The qpdf output produced structural warnings: " +
            utf8(warningSummary(verification))
        );
    }
    if (!verifiedInventory.graphSupported) {
        throw std::runtime_error(
            "The qpdf output failed annotation graph validation: " +
            utf8(verifiedInventory.graphFailure)
        );
    }
    return result;
}

} // namespace

NSData *MPPDFInspectSource(NSData *sourceData, NSError **error)
{
    try {
        QPDF pdf;
        pdf.setAttemptRecovery(false);
        pdf.setSuppressWarnings(true);
        pdf.processMemoryFile(
            "MathPDF source",
            static_cast<char const *>(sourceData.bytes),
            sourceData.length
        );

        bool encrypted = pdf.isEncrypted();
        bool signedDocument = hasReachableSignature(pdf);
        auto inventory = inventoryAnnotations(pdf);
        bool warnings = pdf.anyWarnings();
        bool editable = !encrypted && !signedDocument && !warnings && inventory.graphSupported;

        NSString *reason = @"";
        if (encrypted) {
            reason = @"Encrypted PDFs are read-only in this release.";
        } else if (signedDocument) {
            reason = @"Signed PDFs are read-only because a rewrite would invalidate signatures.";
        } else if (warnings) {
            reason = @"qpdf reported structural warnings; MathPDF will not rewrite this file.";
        } else if (!inventory.graphSupported) {
            reason = inventory.graphFailure;
        }

        return jsonData(@{
            @"editable": @(editable),
            @"reason": reason,
            @"encrypted": @(encrypted),
            @"signed": @(signedDocument),
            @"linearized": @(pdf.isLinearized()),
            @"warnings": @(warnings),
            @"pages": inventory.pages,
        }, error);
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = makeError(
                ErrorCode::invalidSource,
                stringFromUTF8(exception.what())
            );
        }
        return nil;
    }
}

NSData *MPPDFSerializeAnnotationGraph(
    NSData *sourceData,
    NSData *requestJSON,
    NSError **error
)
{
    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:requestJSON options:0 error:&jsonError];
    if (![object isKindOfClass:NSDictionary.class]) {
        if (error != nullptr) {
            *error = jsonError ?: makeError(
                ErrorCode::invalidRequest,
                @"The qpdf mutation request is not a JSON dictionary."
            );
        }
        return nil;
    }

    try {
        return serializeGraph(sourceData, object);
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = makeError(
                ErrorCode::serializationFailed,
                stringFromUTF8(exception.what())
            );
        }
        return nil;
    }
}
