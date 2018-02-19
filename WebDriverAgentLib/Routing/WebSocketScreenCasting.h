//
//  WebSocketScreenCasting.h
//  WebDriverAgentLib
//
//  Created by SHUBHANKAR YASH on 11/01/18.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SocketIO/SocketIO-Swift.h>
#import <objc/runtime.h>
#import "FBApplication.h"
#import "FBResponseJSONPayload.h"
#import "FBScreenshotCommands.h"
#import <WebRTC/WebRTC.h>

@interface WebSocketScreenCasting : NSObject<RTCPeerConnectionDelegate>

@property (nonatomic, strong) RTCPeerConnection *localConnection;
@property (nonatomic, strong) RTCPeerConnection *remoteConnection;
@property (nonatomic, strong) RTCDataChannel *sendChannel;
@property (nonatomic, strong) RTCDataChannel *receiveChannel;
@property (nonatomic, strong) RTCPeerConnectionFactory *factory;

-(void) setSocketConnected: (BOOL) isSocketConnected;
-(void) startScreeing: (SocketIOClient*) clientSocket;

@end
