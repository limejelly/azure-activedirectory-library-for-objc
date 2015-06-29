// Copyright © Microsoft Open Technologies, Inc.
//
// All Rights Reserved
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
// ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
// PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
//
// See the Apache License, Version 2.0 for the specific language
// governing permissions and limitations under the License.


#import "ADALiOS.h"
#import "ADAuthenticationResult.h"
#import "ADAuthenticationResult+Internal.h"
#import "ADTokenCacheStoreItem.h"
#import "ADOAuth2Constants.h"
#import "ADUserInformation.h"

@implementation ADAuthenticationResult (Internal)

-(id) initWithCancellation
{
    ADAuthenticationError* error = [ADAuthenticationError errorFromCancellation];
    
    return [self initWithError:error status:AD_USER_CANCELLED];
}

-(id) initWithItem: (ADTokenCacheStoreItem*) item
multiResourceRefreshToken: (BOOL) multiResourceRefreshToken
{
    self = [super init];
    if (self)
    {
        _status = AD_SUCCEEDED;
        _tokenCacheStoreItem = item;
        _multiResourceRefreshToken = multiResourceRefreshToken;
    }
    return self;
}

-(id) initWithError: (ADAuthenticationError*)error
             status: (ADAuthenticationResultStatus) status
{
    THROW_ON_NIL_ARGUMENT(error);
    
    self = [super init];
    if (self)
    {
        _status = status;
        _error = error;
    }
    return self;
}

/*! Creates an instance of the result from the cache store. */
+(ADAuthenticationResult*) resultFromTokenCacheStoreItem: (ADTokenCacheStoreItem*) item
                               multiResourceRefreshToken: (BOOL) multiResourceRefreshToken
{
    if (item)
    {
        ADAuthenticationError* error;
        [item extractKeyWithError:&error];
        if (error)
        {
            //Bad item, return error:
            return [ADAuthenticationResult resultFromError:error];
        }
        if ([NSString adIsStringNilOrBlank:item.accessToken])
        {
            //Bad item, the access token should be accurate, else an error should be
            //reported instead of this creator:
            ADAuthenticationError* error = [ADAuthenticationError unexpectedInternalError:@"ADAuthenticationResult created from item with no access token."];
            return [ADAuthenticationResult resultFromError:error];
        }
        //The item can be used, just use it:
        return [[ADAuthenticationResult alloc] initWithItem:item multiResourceRefreshToken:multiResourceRefreshToken];
    }
    else
    {
        ADAuthenticationError* error = [ADAuthenticationError unexpectedInternalError:@"ADAuthenticationResult created from nil token item."];
        return [ADAuthenticationResult resultFromError:error];
    }
}

+(ADAuthenticationResult*) resultFromError: (ADAuthenticationError*) error
{
    ADAuthenticationResult* result = [ADAuthenticationResult alloc];
    return [result initWithError:error status:AD_FAILED];
}

+ (ADAuthenticationResult*)resultFromParameterError:(NSString *)details
{
    return [[ADAuthenticationResult alloc] initWithError:[ADAuthenticationError invalidArgumentError:details] status:AD_FAILED];
}

+(ADAuthenticationResult*) resultFromCancellation
{
    ADAuthenticationResult* result = [ADAuthenticationResult alloc];
    return [result initWithCancellation];
}

+(ADAuthenticationResult*) resultFromBrokerResponse: (NSDictionary*) response
{
    ADAuthenticationError* error;
    ADAuthenticationResult* result;
    ADTokenCacheStoreItem* item = nil;
    if([response valueForKey:OAUTH2_ERROR_DESCRIPTION])
    {
        error = [ADAuthenticationError errorFromNSError:[NSError errorWithDomain:ADBrokerResponseErrorDomain code:0 userInfo:nil] errorDetails:[response valueForKey:OAUTH2_ERROR_DESCRIPTION]];
    }
    else
    {
        item = [ADTokenCacheStoreItem new];
        item.authority =  [response valueForKey:OAUTH2_AUTHORITY];
        item.resource = [response valueForKey:OAUTH2_RESOURCE];
        item.clientId = [response valueForKey:OAUTH2_CLIENT_ID];
        item.accessToken = [response valueForKey:OAUTH2_ACCESS_TOKEN];
        item.refreshToken = [response valueForKey:OAUTH2_REFRESH_TOKEN];
        if([response valueForKey:OAUTH2_ID_TOKEN])
        {
            ADUserInformation* info = [ADUserInformation userInformationWithIdToken:[response valueForKey:OAUTH2_ID_TOKEN] error:&error];
            if(!error)
            {
                item.userInformation = info;
            }
        }
    }
    
    result.tokenCacheStoreItem.accessTokenType = @"Bearer";
    // Token response
    id expires_in = [response objectForKey:@"expires_on"];
    NSDate *expires    = nil;
    
    if ( expires_in != nil )
    {
        if ( [expires_in isKindOfClass:[NSString class]] )
        {
            NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
            
            expires = [NSDate dateWithTimeIntervalSinceNow:[formatter numberFromString:expires_in].longValue];
        }
        else if ( [expires_in isKindOfClass:[NSNumber class]] )
        {
            expires = [NSDate dateWithTimeIntervalSinceNow:((NSNumber *)expires_in).longValue];
        }
        else
        {
            AD_LOG_WARN_F(@"Unparsable time", @"The response value for the access token expiration cannot be parsed: %@", expires);
            // Unparseable, use default value
            expires = [NSDate dateWithTimeIntervalSinceNow:3600.0];//1 hour
        }
    }
    else
    {
        AD_LOG_WARN(@"Missing expiration time.", @"The server did not return the expiration time for the access token.");
        expires = [NSDate dateWithTimeIntervalSinceNow:3600.0];//Assume 1hr expiration
    }
    
    result.tokenCacheStoreItem.expiresOn = expires;
    
    
    BOOL isMRRT = item.resource && item.refreshToken;
    if(error)
    {
        result = [ADAuthenticationResult resultFromError:error];
    }
    else
    {
        result = [[ADAuthenticationResult alloc ]initWithItem:item multiResourceRefreshToken:isMRRT];
    }
    
    return result;
}

@end
