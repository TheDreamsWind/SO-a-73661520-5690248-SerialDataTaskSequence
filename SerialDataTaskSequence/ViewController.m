//
//  ViewController.m
//  SerialDataTaskSequence
//
//  Created by Aleksandr Medvedev on 13.09.2022.
//

#import "TDWSerialDataTaskSequence.h"
#import "ViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^TDWKVOReceptionistTask)(NSString *keyPath, id object, NSDictionary<NSKeyValueChangeKey, id> *change, void *context);

@interface TDWKVOReceptionist : NSObject

@property(weak, readonly) id observee;
@property(copy, readonly) NSString *keyPath;
@property(copy, readonly) TDWKVOReceptionistTask callback;
@property(strong, readonly) NSOperationQueue *callbackQueue;
@property(unsafe_unretained, nullable, readonly) void *context;

- (instancetype)initWithObservee:(id)observee
                         keyPath:(NSString *)keyPath
                        callback:(TDWKVOReceptionistTask)callback
                           queue:(NSOperationQueue *)queue
                         context:(nullable void *)context;

@end

NS_ASSUME_NONNULL_END

@implementation TDWKVOReceptionist

#pragma mark Lifecycle

- (instancetype)initWithObservee:(id)observee
                         keyPath:(NSString *)keyPath
                        callback:(TDWKVOReceptionistTask)callback
                           queue:(NSOperationQueue *)queue
                         context:(void *)context {
    if (self = [super init]) {
        _keyPath = [keyPath copy];
        _callback = [callback copy];
        _callbackQueue = queue;
        _context = context;
        [observee addObserver:self
                   forKeyPath:[keyPath copy]
                      options:NSKeyValueObservingOptionNew
                      context:context];
    }
    return self;
}

- (void)dealloc {
    if (_observee) {
        [_observee removeObserver:self forKeyPath:_keyPath];
    }
}

#pragma mark NSObject

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == _context) {
        typeof(self) __weak weakSelf = self;
        [_callbackQueue addOperationWithBlock:^{
            if (!weakSelf) {
                return;
            }
            typeof(weakSelf) __strong strongSelf = weakSelf;
            strongSelf->_callback(keyPath, object, change, context);
        }];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end


#pragma mark -

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel *dataLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
@property (strong, nonatomic) TDWSerialDataTaskSequence *currentDataTaskSequence;
@property (strong, nonatomic) TDWKVOReceptionist *kvoReceptionist;

@end

@implementation ViewController

#pragma mark Actions

- (IBAction)didTapLoadDataButton:(UIButton *)sender {
    if (_currentDataTaskSequence) {
        [self p_unsubscribeFromTaskSequenceProgress:_currentDataTaskSequence];
        [_currentDataTaskSequence cancel];
        self.currentDataTaskSequence = nil;
    }
    
    // Creates a file to write to
    NSError *__autoreleasing documentDirectorySearchError;
    NSURL *documentsPathURL = [NSFileManager.defaultManager URLForDirectory:NSDocumentDirectory
                                                                   inDomain:NSUserDomainMask
                                                          appropriateForURL:nil
                                                                     create:YES
                                                                      error:&documentDirectorySearchError];
    if (documentDirectorySearchError) {
        NSLog(@"Could not located the documents directory: %@", documentDirectorySearchError);
        return;
    }

    NSURL *filePathURL = [NSURL fileURLWithPath:@"File.data" relativeToURL:documentsPathURL];
    [NSFileManager.defaultManager createFileAtPath:filePathURL.path contents:nil attributes:nil];

    typeof(self) __weak weakSelf = self;
    TDWSerialDataTaskSequence *dataTaskSequence = [[TDWSerialDataTaskSequence alloc] initWithURLArray:@[
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-5s.mp4"],
//        [[NSURL alloc] initWithString:@"https://error.url/sample-20s.mp4"], // uncomment to check error scenario
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-30s.mp4"],
        [[NSURL alloc] initWithString:@"https://download.samplelib.com/mp4/sample-20s.mp4"]
    ] filePathURL:filePathURL callback:^(NSURL * _Nonnull filePath, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf) {
                return;
            }
            
            typeof(weakSelf) __strong strongSelf = weakSelf;
            if (error) {
                strongSelf->_dataLabel.text = error.localizedDescription;
            } else {
                NSError *__autoreleasing fileReadError;
                NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:filePath.path
                                                                                                                  error:&fileReadError];
                if (fileReadError) {
                    strongSelf->_dataLabel.text = fileReadError.localizedDescription;
                } else {
                    long long dataLength = ((NSNumber *)attributes[NSFileSize]).longLongValue;
                    strongSelf->_dataLabel.text = [NSString stringWithFormat:@"File Size loaded: %lld bytes.\nFile path: %@", dataLength, filePath.path];
                }

            }
        });
    }];
    if (!dataTaskSequence) {
        NSLog(@"Failed to create data task sequence");
        return;
    }

    _dataLabel.text = @"Loading...";
    [self p_subscribeToTaskSequenceProgress:dataTaskSequence];
    [dataTaskSequence resume];
    self.currentDataTaskSequence = dataTaskSequence;
}

#pragma mark Private

- (void)p_subscribeToTaskSequenceProgress:(TDWSerialDataTaskSequence *)dataTaskSequence {
    _progressView.observedProgress = dataTaskSequence.progress;
    
    static void *ProgressViewProgressContext = &ProgressViewProgressContext;
    typeof(self) __weak weakSelf = self;
    self.kvoReceptionist = [[TDWKVOReceptionist alloc] initWithObservee:dataTaskSequence.progress keyPath:@"fractionCompleted" callback:^(NSString * _Nonnull keyPath, id _Nonnull object, NSDictionary<NSKeyValueChangeKey, id> *_Nonnull change, void *_Nonnull context) {
        if (!weakSelf) {
            return;
        }
        typeof(weakSelf) __strong strongSelf = weakSelf;
        double fractionCompleted = ((NSNumber *)change[NSKeyValueChangeNewKey]).doubleValue;
        unsigned percentCompleted = fractionCompleted * 100;
        strongSelf->_dataLabel.text = [NSString stringWithFormat:@"Loading %d%%", percentCompleted];
    } queue:NSOperationQueue.mainQueue context:ProgressViewProgressContext];
}

- (void)p_unsubscribeFromTaskSequenceProgress:(TDWSerialDataTaskSequence *)dataTaskSequence {
    _progressView.observedProgress = nil;
    self.kvoReceptionist = nil;
}

@end
