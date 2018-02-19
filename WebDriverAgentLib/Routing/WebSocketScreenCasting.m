//
//  WebSocketScreenCasting.m
//  WebDriverAgentLib
//
//  Created by SHUBHANKAR YASH on 11/01/18.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import "WebSocketScreenCasting.h"

@interface WebSocketScreenCasting()
@property (nonatomic, assign) BOOL isSocketConnected;
@end


@implementation WebSocketScreenCasting

-(void) setSocketConnected: (BOOL) isSocketConnected {
  self.isSocketConnected = isSocketConnected;
}

-(void) pushScreenShot:(SocketIOClient*) clientSocket andOrientation:(UIInterfaceOrientation) orientation andScreenWidth:(CGFloat) screenWidth andScreenHeight:(CGFloat) screenHeight {
  FBResponseJSONPayload *fbJSONPayload = [FBScreenshotCommands handleGetScreenshotWithScreenMeta:orientation andScreenWidth:screenWidth andScreenHeight:screenHeight];
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:fbJSONPayload.dictionary
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
  NSArray *dataArray = [[NSArray alloc] initWithObjects:jsonData, nil];
  
  RTCConfiguration *configuration = [[RTCConfiguration alloc] init];
  configuration.bundlePolicy = RTCBundlePolicyBalanced;
  
  RTCIceServer *server = [[RTCIceServer alloc] initWithURLStrings: @[@"http://172.20.52.133:8000"]];
  configuration.iceServers = @[server];
  
  RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints: [[NSDictionary alloc] init] optionalConstraints: [[NSDictionary alloc] init]];
  
  self.localConnection = [self.factory peerConnectionWithConfiguration:configuration constraints:constraints delegate:self];
  self.remoteConnection = [self.factory peerConnectionWithConfiguration:configuration constraints:constraints delegate:self];
  
  RTCDataChannelConfiguration *dataChannelConfiguration = [[RTCDataChannelConfiguration alloc] init];
  dataChannelConfiguration.isOrdered = YES;
  self.sendChannel = [self.localConnection dataChannelForLabel:@"test" configuration:dataChannelConfiguration];

  [self.localConnection offerForConstraints:constraints completionHandler:^(RTCSessionDescription * _Nullable firstDescription, NSError * _Nullable error) {
    [self.localConnection setLocalDescription:firstDescription completionHandler:nil];
    [self.remoteConnection setRemoteDescription:firstDescription completionHandler:nil];
    [self.remoteConnection answerForConstraints:constraints completionHandler:^(RTCSessionDescription * _Nullable secondDescription, NSError * _Nullable error) {
      [self.localConnection setRemoteDescription:secondDescription completionHandler:nil];
      [self.remoteConnection setLocalDescription:secondDescription completionHandler:nil];
    }];
  }];
  
  [clientSocket emit:@"screenShot" with: dataArray];
}

-(void) startScreeing: (SocketIOClient*) clientSocket {
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
  UIInterfaceOrientation interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
  CGSize screenSize = FBApplication.fb_activeApplication.frame.size;
  CGFloat width = screenSize.width;
  CGFloat height = screenSize.height;
  
  self.factory = [[RTCPeerConnectionFactory alloc] init];
//  [RTCPeerConnectionFactory initializeSSL];
  __weak WebSocketScreenCasting *weakSelf = self;
  dispatch_async(queue, ^{
    while(weakSelf.isSocketConnected) {
      WebSocketScreenCasting *strongSelf = weakSelf;
      [strongSelf pushScreenShot: clientSocket andOrientation:interfaceOrientation andScreenWidth:width andScreenHeight:height];
    }
  });
}

-(void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {
  
}

-(void) peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {
  
}

-(void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {
  
}

-(void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate {
  
}

-(void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {
  
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {
  
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
  
}

/** Called any time the IceGatheringState changes. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
  
}

@end
