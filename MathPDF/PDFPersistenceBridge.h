#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSData * _Nullable MPPDFInspectSource(
    NSData *sourceData,
    NSError * _Nullable * _Nullable error
);

FOUNDATION_EXPORT NSData * _Nullable MPPDFSerializeAnnotationGraph(
    NSData *sourceData,
    NSData *requestJSON,
    NSError * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
