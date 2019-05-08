//
//  Compat.m
//  SocketRocket
//
//  Created by kbinani on 2019/05/08.
//

#import <Foundation/Foundation.h>
#import <SocketRocket/SocketRocket.h>
#import "SocketRocket-Swift.h"

static void compat_SRSecurityPolicy() {
    [[SRSecurityPolicy alloc] init];
    [[SRSecurityPolicy alloc] initWithCertificateChainValidationEnabled:YES];
    SRSecurityPolicy *policy = [SRSecurityPolicy defaultPolicy];
    [SRSecurityPolicy pinnningPolicyWithCertificates: NSArray.new];
    NSInputStream *stream = [[NSInputStream alloc] initWithFileAtPath:@""];
    [policy updateSecurityOptionsInStream:stream];
    SecTrustRef trust = NULL;
    SecTrustCreateWithCertificates(CFArrayCreate(NULL, NULL, 0, NULL), NULL, &trust);
    [policy evaluateServerTrust:trust forDomain:@""];
}
