//
//  MGTwitterEngine.m
//  MGTwitterEngine
//
//  Created by Matt Gemmell on 10/02/2008.
//  Copyright 2008 Magic Aubergine.
//

#import "MGTwitterEngine.h"
#import "MGTwitterStatusesParser.h"
#import "MGTwitterUsersParser.h"
#import "MGTwitterMessagesParser.h"
#import "MGTwitterHTTPURLConnection.h"

#define TWITTER_DOMAIN          @"twitter.com"
#define HTTP_POST_METHOD        @"POST"
#define MAX_MESSAGE_LENGTH      140 // Twitter recommends tweets of max 140 chars

#define DEFAULT_CLIENT_NAME     @"MGTwitterEngine"
#define DEFAULT_CLIENT_VERSION  @"1.0"
#define DEFAULT_CLIENT_URL      @"http://mattgemmell.com/"

#define URL_REQUEST_TIMEOUT     25.0 // Twitter usually fails quickly if it's going to fail at all.


@interface MGTwitterEngine (PrivateMethods)

// Utility methods
- (NSDateFormatter *)_HTTPDateFormatter;
- (NSString *)_queryStringWithBase:(NSString *)base parameters:(NSDictionary *)params prefixed:(BOOL)prefixed;
- (NSDate *)_HTTPToDate:(NSString *)httpDate;
- (NSString *)_dateToHTTP:(NSDate *)date;
- (NSString *)_encodeString:(NSString *)string;

// Connection/Request methods
- (NSString *)_sendRequestWithMethod:(NSString *)method 
                                path:(NSString *)path 
                     queryParameters:(NSDictionary *)params
                                body:(NSString *)body 
                         requestType:(MGTwitterRequestType)requestType 
                        responseType:(MGTwitterResponseType)responseType;

// Parsing methods
- (void)_parseXMLForConnection:(MGTwitterHTTPURLConnection *)connection;

@end


@implementation MGTwitterEngine


#pragma mark Constructors


+ (MGTwitterEngine *)twitterEngineWithDelegate:(NSObject *)theDelegate
{
    return [[[MGTwitterEngine alloc] initWithDelegate:theDelegate] autorelease];
}


- (MGTwitterEngine *)initWithDelegate:(NSObject *)newDelegate
{
    if (self = [super init]) {
        _delegate = newDelegate; // deliberately weak reference
        _connections = [[NSMutableDictionary alloc] initWithCapacity:0];
        _clientName = [DEFAULT_CLIENT_NAME retain];
        _clientVersion = [DEFAULT_CLIENT_VERSION retain];
        _clientURL = [DEFAULT_CLIENT_URL retain];
        _secureConnection = YES;
		_clearsCookies = NO;
    }
    
    return self;
}


- (void)dealloc
{
    _delegate = nil;
    
    [[_connections allValues] makeObjectsPerformSelector:@selector(cancel)];
    [_connections release];
    
    [_username release];
    [_password release];
    [_clientName release];
    [_clientVersion release];
    [_clientURL release];
    [_clientSourceToken release];
    
    [super dealloc];
}


#pragma mark Configuration and Accessors


+ (NSString *)version
{
    // 1.0.0 = 22 Feb 2008
    // 1.0.1 = 26 Feb 2008
    // 1.0.2 = 04 Mar 2008
    // 1.0.3 = 04 Mar 2008
	// 1.0.4 = 11 Apr 2008
    return @"1.0.4";
}


- (NSString *)username
{
    return [[_username retain] autorelease];
}


- (NSString *)password
{
    return [[_password retain] autorelease];
}


- (void)setUsername:(NSString *)newUsername password:(NSString *)newPassword
{
    // Set new credentials.
    [_username release];
    _username = [newUsername retain];
    [_password release];
    _password = [newPassword retain];
    
	if ([self clearsCookies]) {
		// Remove all cookies for twitter, to ensure next connection uses new credentials.
		NSString *urlString = [NSString stringWithFormat:@"%@://%@", 
							   (_secureConnection) ? @"https" : @"http", 
							   TWITTER_DOMAIN];
		NSURL *url = [NSURL URLWithString:urlString];
		
		NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
		NSEnumerator *enumerator = [[cookieStorage cookiesForURL:url] objectEnumerator];
		NSHTTPCookie *cookie = nil;
		while (cookie = [enumerator nextObject]) {
			[cookieStorage deleteCookie:cookie];
		}
	}
}


- (NSString *)clientName
{
    return [[_clientName retain] autorelease];
}


- (NSString *)clientVersion
{
    return [[_clientVersion retain] autorelease];
}


- (NSString *)clientURL
{
    return [[_clientURL retain] autorelease];
}


- (NSString *)clientSourceToken
{
    return [[_clientSourceToken retain] autorelease];
}


- (void)setClientName:(NSString *)name version:(NSString *)version URL:(NSString *)url token:(NSString *)token;
{
    [_clientName release];
    _clientName = [name retain];
    [_clientVersion release];
    _clientVersion = [version retain];
    [_clientURL release];
    _clientURL = [url retain];
    [_clientSourceToken release];
    _clientSourceToken = [token retain];
}


- (BOOL)usesSecureConnection
{
    return _secureConnection;
}


- (void)setUsesSecureConnection:(BOOL)flag
{
    _secureConnection = flag;
}


- (BOOL)clearsCookies
{
	return _clearsCookies;
}


- (void)setClearsCookies:(BOOL)flag
{
	_clearsCookies = flag;
}


#pragma mark Connection methods


- (int)numberOfConnections
{
    return [_connections count];
}


- (NSArray *)connectionIdentifiers
{
    return [_connections allKeys];
}


- (void)closeConnection:(NSString *)identifier
{
    MGTwitterHTTPURLConnection *connection = [_connections objectForKey:identifier];
    if (connection) {
        [connection cancel];
        [_connections removeObjectForKey:identifier];
    }
}


- (void)closeAllConnections
{
    [[_connections allValues] makeObjectsPerformSelector:@selector(cancel)];
    [_connections removeAllObjects];
}


#pragma mark Utility methods


- (NSDateFormatter *)_HTTPDateFormatter
{
    // Returns a formatter for dates in HTTP format (i.e. RFC 822, updated by RFC 1123).
    // e.g. "Sun, 06 Nov 1994 08:49:37 GMT"
    return [[[NSDateFormatter alloc]
             initWithDateFormat:@"%a, %d %b %Y %H:%M:%S GMT" 
             allowNaturalLanguage:NO] autorelease];
}


- (NSString *)_queryStringWithBase:(NSString *)base parameters:(NSDictionary *)params prefixed:(BOOL)prefixed
{
    // Append base if specified.
    NSMutableString *str = [NSMutableString stringWithCapacity:0];
    if (base) {
        [str appendString:base];
    }
    
    // Append each name-value pair.
    if (params) {
        int i;
        NSArray *names = [params allKeys];
        for (i = 0; i < [names count]; i++) {
            if (i == 0 && prefixed) {
                [str appendString:@"?"];
            } else if (i > 0) {
                [str appendString:@"&"];
            }
            NSString *name = [names objectAtIndex:i];
            [str appendString:[NSString stringWithFormat:@"%@=%@", 
             name, [self _encodeString:[params objectForKey:name]]]];
        }
    }
    
    return str;
}


- (NSDate *)_HTTPToDate:(NSString *)httpDate
{
    NSDateFormatter *dateFormatter = [self _HTTPDateFormatter];
    return [dateFormatter dateFromString:httpDate];
}


- (NSString *)_dateToHTTP:(NSDate *)date
{
    NSDateFormatter *dateFormatter = [self _HTTPDateFormatter];
    return [dateFormatter stringFromDate:date];
}


- (NSString *)_encodeString:(NSString *)string
{
    NSMutableString *tempStr = [NSMutableString stringWithString:string];
    [tempStr replaceOccurrencesOfString:@" " 
                             withString:@"+" 
                                options:NSLiteralSearch 
                                  range:NSMakeRange(0, [string length])];
    CFStringRef strRef = CFURLCreateStringByAddingPercentEscapes(NULL, 
                                                                 (CFStringRef)tempStr, 
                                                                 NULL, 
                                                                 (CFStringRef)@";/?:@&=$,", 
                                                                 kCFStringEncodingUTF8);
    NSString *replaced = [NSString stringWithString:(NSString *)strRef];
    CFRelease(strRef);
    return replaced;
}


- (NSString *)getImageAtURL:(NSString *)urlString
{
    // This is a method implemented for the convenience of the client, 
    // allowing asynchronous downloading of users' Twitter profile images.
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return nil;
    }
    
    // Construct an NSMutableURLRequest for the URL and set appropriate request method.
    NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL:url 
                                                              cachePolicy:NSURLRequestReloadIgnoringCacheData 
                                                          timeoutInterval:URL_REQUEST_TIMEOUT];
    
    // Create a connection using this request, with the default timeout and caching policy, 
    // and appropriate Twitter request and response types for parsing and error reporting.
    MGTwitterHTTPURLConnection *connection;
    connection = [[MGTwitterHTTPURLConnection alloc] initWithRequest:theRequest 
                                                            delegate:self 
                                                         requestType:MGTwitterImageRequest 
                                                        responseType:MGTwitterImage];
    
    if (!connection) {
        return nil;
    } else {
        [_connections setObject:connection forKey:[connection identifier]];
        [connection release];
    }
    
    return [connection identifier];
}


#pragma mark Request sending methods


- (NSString *)_sendRequestWithMethod:(NSString *)method 
                                path:(NSString *)path 
                     queryParameters:(NSDictionary *)params 
                                body:(NSString *)body 
                         requestType:(MGTwitterRequestType)requestType 
                        responseType:(MGTwitterResponseType)responseType
{
    // Construct appropriate URL string.
    NSString *fullPath = path;
    if (params) {
        fullPath = [self _queryStringWithBase:fullPath parameters:params prefixed:YES];
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@://%@:%@@%@/%@", 
                           (_secureConnection) ? @"https" : @"http", 
                           [self _encodeString:_username], [self _encodeString:_password], 
                           TWITTER_DOMAIN, fullPath];
						   
	NSLog(@"url: %@",urlString);
	
	// TODO remove!
  // urlString = @"http://0.0.0.0:8000/eg.xml";
    
    NSURL *finalURL = [NSURL URLWithString:urlString];
    if (!finalURL) {
        return nil;
    }
    
    // Construct an NSMutableURLRequest for the URL and set appropriate request method.
    NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL:finalURL 
                                                              cachePolicy:NSURLRequestReloadIgnoringCacheData 
                                                          timeoutInterval:URL_REQUEST_TIMEOUT];
    if (method) {
        [theRequest setHTTPMethod:method];
    }
    [theRequest setHTTPShouldHandleCookies:NO];
    
    // Set headers for client information, for tracking purposes at Twitter.
    [theRequest setValue:_clientName    forHTTPHeaderField:@"X-Twitter-Client"];
    [theRequest setValue:_clientVersion forHTTPHeaderField:@"X-Twitter-Client-Version"];
    [theRequest setValue:_clientURL     forHTTPHeaderField:@"X-Twitter-Client-URL"];
    
    // Set the request body if this is a POST request.
    BOOL isPOST = (method && [method isEqualToString:HTTP_POST_METHOD]);
    if (isPOST) {
        // Set request body, if specified (hopefully so), with 'source' parameter if appropriate.
        NSString *finalBody = [@"" stringByAppendingString:body];
        if (_clientSourceToken) {
            finalBody = [finalBody stringByAppendingString:[NSString stringWithFormat:@"%@source=%@", 
                                                            (body) ? @"&" : @"?" , 
                                                            _clientSourceToken]];
        }
        
        if (finalBody) {
            [theRequest setHTTPBody:[finalBody dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    
    // Create a connection using this request, with the default timeout and caching policy, 
    // and appropriate Twitter request and response types for parsing and error reporting.
    MGTwitterHTTPURLConnection *connection;
    connection = [[MGTwitterHTTPURLConnection alloc] initWithRequest:theRequest 
                                                            delegate:self 
                                                         requestType:requestType 
                                                        responseType:responseType];
    
    if (!connection) {
        return nil;
    } else {
        [_connections setObject:connection forKey:[connection identifier]];
        [connection release];
    }
    
    return [connection identifier];
}


#pragma mark Parsing methods


- (void)_parseXMLForConnection:(MGTwitterHTTPURLConnection *)connection
{
    NSString *identifier = [[[connection identifier] copy] autorelease];
    NSData *xmlData = [[[connection data] copy] autorelease];
    MGTwitterRequestType requestType = [connection requestType];
    MGTwitterResponseType responseType = [connection responseType];
    
    // Determine which type of parser to use.
    switch (responseType) {
        case MGTwitterStatuses:
        case MGTwitterStatus:
            [MGTwitterStatusesParser parserWithXML:xmlData delegate:self 
                              connectionIdentifier:identifier requestType:requestType 
                                      responseType:responseType];
            break;
        case MGTwitterUsers:
        case MGTwitterUser:
            [MGTwitterUsersParser parserWithXML:xmlData delegate:self 
                           connectionIdentifier:identifier requestType:requestType 
                                   responseType:responseType];
            break;
        case MGTwitterDirectMessages:
        case MGTwitterDirectMessage:
            [MGTwitterMessagesParser parserWithXML:xmlData delegate:self 
                              connectionIdentifier:identifier requestType:requestType 
                                      responseType:responseType];
            break;
        default:
            break;
    }
}


#pragma mark MGTwitterParserDelegate methods


- (void)parsingSucceededForRequest:(NSString *)identifier 
                    ofResponseType:(MGTwitterResponseType)responseType 
                 withParsedObjects:(NSArray *)parsedObjects
{
    // Forward appropriate message to _delegate, depending on responseType.
    switch (responseType) {
        case MGTwitterStatuses:
        case MGTwitterStatus:
            [_delegate statusesReceived:parsedObjects forRequest:identifier];
            break;
        case MGTwitterUsers:
        case MGTwitterUser:
            [_delegate userInfoReceived:parsedObjects forRequest:identifier];
            break;
        case MGTwitterDirectMessages:
        case MGTwitterDirectMessage:
            [_delegate directMessagesReceived:parsedObjects forRequest:identifier];
            break;
        default:
            break;
    }
}


- (void)parsingFailedForRequest:(NSString *)requestIdentifier 
                 ofResponseType:(MGTwitterResponseType)responseType 
                      withError:(NSError *)error
{
    [_delegate requestFailed:requestIdentifier withError:error];
}


#pragma mark NSURLConnection delegate methods


- (void)connection:(MGTwitterHTTPURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    // This method is called when the server has determined that it has enough information to create the NSURLResponse.
    // it can be called multiple times, for example in the case of a redirect, so each time we reset the data.
    [connection resetDataLength];
    
    // Get response code.
    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
    int statusCode = [resp statusCode];
    
    if (statusCode >= 400) {
        // Assume failure, and report to delegate.
        NSError *error = [NSError errorWithDomain:@"HTTP" code:statusCode userInfo:nil];
        [_delegate requestFailed:[connection identifier] withError:error];
        
        // Destroy the connection.
        [connection cancel];
        [_connections removeObjectForKey:[connection identifier]];
        
    } else if (statusCode == 304 || [connection responseType] == MGTwitterGeneric) {
        // Not modified, or generic success.
        [_delegate requestSucceeded:[connection identifier]];
        if (statusCode == 304) {
            [self parsingSucceededForRequest:[connection identifier] 
                              ofResponseType:[connection responseType] 
                           withParsedObjects:[NSArray array]];
        }
        
        // Destroy the connection.
        [connection cancel];
        [_connections removeObjectForKey:[connection identifier]];
    }
    
    if (NO) {
        // Display headers for debugging.
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        NSLog(@"(%d) [%@]:\r%@", 
              [resp statusCode], 
              [NSHTTPURLResponse localizedStringForStatusCode:[resp statusCode]], 
              [resp allHeaderFields]);
    }
}


- (void)connection:(MGTwitterHTTPURLConnection *)connection didReceiveData:(NSData *)data
{
    // Append the new data to the receivedData.
    [connection appendData:data];
}


- (void)connection:(MGTwitterHTTPURLConnection *)connection didFailWithError:(NSError *)error
{
    // Inform delegate.
    [_delegate requestFailed:[connection identifier] withError:error];
    
    // Release the connection.
    [_connections removeObjectForKey:[connection identifier]];
}


- (void)connectionDidFinishLoading:(MGTwitterHTTPURLConnection *)connection
{
    // Inform delegate.
    [_delegate requestSucceeded:[connection identifier]];
    
    NSData *receivedData = [connection data];
    if (receivedData) {
        if (NO) {
            // Dump data as string for debugging.
            NSString *dataString = [NSString stringWithUTF8String:[receivedData bytes]];
            NSLog(@"Succeeded! Received %d bytes of data:\r\r%@", [receivedData length], dataString);
        }
        
        if (NO) {
            // Dump XML to file for debugging.
            NSString *dataString = [NSString stringWithUTF8String:[receivedData bytes]];
            [dataString writeToFile:[@"~/Desktop/twitter_messages.xml" stringByExpandingTildeInPath] 
                         atomically:NO encoding:NSUnicodeStringEncoding error:NULL];
        }
        
        if ([connection responseType] == MGTwitterImage) {
#if TARGET_OS_ASPEN
            // Create UIImage from data.
            UIImage *image = [[[UIImage alloc] initWithData:[connection data]] autorelease];
#else
            // Create NSImage from data.
            NSImage *image = [[[NSImage alloc] initWithData:[connection data]] autorelease];
#endif
            
            // Inform delegate.
            [_delegate imageReceived:image forRequest:[connection identifier]];
        } else {
            // Parse XML appropriately.
            [self _parseXMLForConnection:connection];
        }
    }
    
    // Release the connection.
    [_connections removeObjectForKey:[connection identifier]];
}


#pragma mark -
#pragma mark Twitter API methods
#pragma mark -


#pragma mark Account methods


- (NSString *)checkUserCredentials
{
    NSString *path = @"account/verify_credentials.xml";
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterGeneric];
}


- (NSString *)endUserSession
{
    NSString *path = @"account/end_session"; // deliberately no format specified
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterGeneric];
}


- (NSString *)enableUpdatesFor:(NSString *)username
{
    // i.e. follow
    if (!username) {
        return nil;
    }
    NSString *path = [NSString stringWithFormat:@"friendships/create/%@.xml", username];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterUser];
}


- (NSString *)disableUpdatesFor:(NSString *)username
{
    // i.e. no longer follow
    if (!username) {
        return nil;
    }
    NSString *path = [NSString stringWithFormat:@"friendships/destroy/%@.xml", username];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterUser];
}


- (NSString *)enableNotificationsFor:(NSString *)username
{
    if (!username) {
        return nil;
    }
    NSString *path = [NSString stringWithFormat:@"notifications/follow/%@.xml", username];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterUser];
}


- (NSString *)disableNotificationsFor:(NSString *)username
{
    if (!username) {
        return nil;
    }
    NSString *path = [NSString stringWithFormat:@"notifications/leave/%@.xml", username];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterUser];
}


#pragma mark Retrieving updates


- (NSString *)getFollowedTimelineFor:(NSString *)username since:(NSDate *)date startingAtPage:(int)pageNum
{
    NSString *path = @"statuses/friends_timeline.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (date) {
        [params setObject:[self _dateToHTTP:date] forKey:@"since"];
    }
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    if (username) {
        path = [NSString stringWithFormat:@"statuses/friends_timeline/%@.xml", username];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterStatusesRequest 
                           responseType:MGTwitterStatuses];
}


- (NSString *)getUserTimelineFor:(NSString *)username since:(NSDate *)date count:(int)numUpdates
{
    NSString *path = @"statuses/user_timeline.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (date) {
        [params setObject:[self _dateToHTTP:date] forKey:@"since"];
    }
    if (numUpdates > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", numUpdates] forKey:@"count"];
    }
    if (username) {
        path = [NSString stringWithFormat:@"statuses/user_timeline/%@.xml", username];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterStatusesRequest 
                           responseType:MGTwitterStatuses];
}


- (NSString *)getUserUpdatesArchiveStartingAtPage:(int)pageNum
{
    NSString *path = @"account/archive.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterStatusesRequest 
                           responseType:MGTwitterStatuses];
}


- (NSString *)getPublicTimelineSinceID:(int)updateID
{
    NSString *path = @"statuses/public_timeline.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (updateID > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", updateID] forKey:@"since_id"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterStatusesRequest 
                           responseType:MGTwitterStatuses];
}


- (NSString *)getRepliesStartingAtPage:(int)pageNum
{
    NSString *path = @"statuses/replies.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterRepliesRequest 
                           responseType:MGTwitterStatuses];
}


- (NSString *)getFavoriteUpdatesFor:(NSString *)username startingAtPage:(int)pageNum
{
    NSString *path = @"favorites.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    if (username) {
        path = [NSString stringWithFormat:@"favorites/%@.xml", username];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterStatusesRequest 
                           responseType:MGTwitterStatuses];
}


- (NSString *)getUpdate:(int)updateID
{
    NSString *path = [NSString stringWithFormat:@"statuses/show/%d.xml", updateID];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterStatusesRequest 
                           responseType:MGTwitterStatus];
}


#pragma mark Retrieving direct messages


- (NSString *)getDirectMessagesSince:(NSDate *)date startingAtPage:(int)pageNum
{
    NSString *path = @"direct_messages.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (date) {
        [params setObject:[self _dateToHTTP:date] forKey:@"since"];
    }
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterDirectMessagesRequest 
                           responseType:MGTwitterDirectMessages];
}


- (NSString *)getDirectMessagesSinceID:(int)updateID startingAtPage:(int)pageNum
{
    NSString *path = @"direct_messages.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (updateID > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", updateID] forKey:@"since_id"];
    }
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterDirectMessagesRequest 
                           responseType:MGTwitterDirectMessages];
}


- (NSString *)getSentDirectMessagesSince:(NSDate *)date startingAtPage:(int)pageNum
{
    NSString *path = @"direct_messages/sent.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (date) {
        [params setObject:[self _dateToHTTP:date] forKey:@"since"];
    }
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterDirectMessagesRequest 
                           responseType:MGTwitterDirectMessages];
}


- (NSString *)getSentDirectMessagesSinceID:(int)updateID startingAtPage:(int)pageNum
{
    NSString *path = @"direct_messages/sent.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (updateID > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", updateID] forKey:@"since_id"];
    }
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterDirectMessagesRequest 
                           responseType:MGTwitterDirectMessages];
}


#pragma mark Retrieving user information


- (NSString *)getUserInformationFor:(NSString *)username
{
    if (!username) {
        return nil;
    }
    NSString *path = [NSString stringWithFormat:@"users/show/%@.xml", username];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterUserInfoRequest 
                           responseType:MGTwitterUser];
}


- (NSString *)getUserInformationForEmail:(NSString *)email
{
    NSString *path = @"users/show.xml";
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (email) {
        [params setObject:email forKey:@"email"];
    } else {
        return nil;
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterUserInfoRequest 
                           responseType:MGTwitterUser];
}


- (NSString *)getRecentlyUpdatedFriendsFor:(NSString *)username startingAtPage:(int)pageNum
{
    NSString *path = @"statuses/friends.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (username) {
        path = [NSString stringWithFormat:@"statuses/friends/%@.xml", username];
    }
    if (pageNum > 0) {
        [params setObject:[NSString stringWithFormat:@"%d", pageNum] forKey:@"page"];
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterUserInfoRequest 
                           responseType:MGTwitterUsers];
}


- (NSString *)getFollowersIncludingCurrentStatus:(BOOL)flag
{
    NSString *path = @"statuses/followers.xml";
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    if (!flag) {
        [params setObject:@"true" forKey:@"lite"]; // slightly bizarre, but correct.
    }
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:params body:nil 
                            requestType:MGTwitterUserInfoRequest 
                           responseType:MGTwitterUsers];
}


- (NSString *)getFeaturedUsers
{
    NSString *path = @"statuses/featured.xml";
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterUserInfoRequest 
                           responseType:MGTwitterUsers];
}


#pragma mark Sending and editing updates


- (NSString *)sendUpdate:(NSString *)status
{
    return [self sendUpdate:status inReplyTo:nil];
}


- (NSString *)sendUpdate:(NSString *)status inReplyTo:(NSString *)updateID
{
    if (!status) {
        return nil;
    }
    
    NSString *path = @"statuses/update.xml";
    
    NSString *trimmedText = status;
    if ([trimmedText length] > MAX_MESSAGE_LENGTH) {
        trimmedText = [trimmedText substringToIndex:MAX_MESSAGE_LENGTH];
    }
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    [params setObject:trimmedText forKey:@"status"];
    if (updateID) {
        [params setObject:updateID forKey:@"reference_id"];
    }
    NSString *body = [self _queryStringWithBase:nil parameters:params prefixed:NO];
    
    return [self _sendRequestWithMethod:HTTP_POST_METHOD path:path 
                        queryParameters:params body:body 
                            requestType:MGTwitterStatusSend 
                           responseType:MGTwitterStatus];
}


- (NSString *)deleteUpdate:(int)updateID
{
    NSString *path = [NSString stringWithFormat:@"statuses/destroy/%d.xml", updateID];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterGeneric];
}


- (NSString *)markUpdate:(int)updateID asFavorite:(BOOL)flag
{
    NSString *path = [NSString stringWithFormat:@"favorites/%@/%d.xml", 
                      (flag) ? @"create" : @"destroy" ,
                      updateID];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterStatus];
}


#pragma mark Sending and editing direct messages


- (NSString *)sendDirectMessage:(NSString *)message to:(NSString *)username
{
    if (!message || !username) {
        return nil;
    }
    
    NSString *path = @"direct_messages/new.xml";
    
    NSString *trimmedText = message;
    if ([trimmedText length] > MAX_MESSAGE_LENGTH) {
        trimmedText = [trimmedText substringToIndex:MAX_MESSAGE_LENGTH];
    }
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:0];
    [params setObject:trimmedText forKey:@"text"];
    [params setObject:username forKey:@"user"];
    NSString *body = [self _queryStringWithBase:nil parameters:params prefixed:NO];
    
    return [self _sendRequestWithMethod:HTTP_POST_METHOD path:path 
                        queryParameters:params body:body 
                            requestType:MGTwitterDirectMessageSend 
                           responseType:MGTwitterDirectMessage];
}


- (NSString *)deleteDirectMessage:(int)updateID
{
    NSString *path = [NSString stringWithFormat:@"direct_messages/destroy/%d.xml", updateID];
    
    return [self _sendRequestWithMethod:nil path:path queryParameters:nil body:nil 
                            requestType:MGTwitterAccountRequest 
                           responseType:MGTwitterGeneric];
}


@end
