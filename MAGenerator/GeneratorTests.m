//
//  GeneratorTests.m
//  MAGenerator
//
//  Created by Michael Ash on 10/21/09.
//

#import "MAGenerator.h"


GENERATOR(int, Primes(void), (void))
{
    __block int n;
    __block int i;
    GENERATOR_BEGIN(void)
    {
        for(n = 2; ; n++)
        {
            for(i = 2; i < n; i++)
                if(n % i == 0)
                    break;
            if(i == n)
                GENERATOR_YIELD(n);
        }
    }
    GENERATOR_END
}

GENERATOR(NSArray *, ArrayBuilder(void), (id obj))
{
    __block NSMutableArray *array = nil;
    GENERATOR_BEGIN(id obj)
    {
        array = [[NSMutableArray alloc] init];
        for(;;)
            if(obj)
            {
                [array addObject: obj];
                GENERATOR_YIELD((NSArray *)array);
            }
    }
    GENERATOR_CLEANUP
    {
        NSLog(@"Cleaning up");
        [array release];
    }
    GENERATOR_END
}

GENERATOR_DECL(NSString *, WordParser(void), (unichar ch));

GENERATOR(NSString *, WordParser(void), (unichar ch))
{
    NSMutableString *buffer = [NSMutableString string];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    GENERATOR_BEGIN(unichar ch)
    {
        for(;;)
        {
            if(ch == 0 || [whitespace characterIsMember: ch])
            {
                GENERATOR_YIELD([buffer length] ? (NSString *)buffer : nil);
                [buffer setString: @""];
            }
            else
            {
                [buffer appendFormat: @"%C", ch];
                GENERATOR_YIELD((NSString *)nil);
            }
        }
    }
    GENERATOR_END
}

GENERATOR(int, Counter(int start, int end), (void))
{
    __block int n;
    GENERATOR_BEGIN(void)
    {
        for(n = start; n <= end; n++)
            GENERATOR_YIELD(n);
        for(;;)
            GENERATOR_YIELD(-1);
    }
    GENERATOR_END
}

GENERATOR(id, FileFinder(NSString *path, NSString *extension), (void))
{
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath: path];
    __block NSString *subpath;
    GENERATOR_BEGIN(void)
    {
        while((subpath = [enumerator nextObject]))
        {
            if([[subpath pathExtension] isEqualToString: extension])
                GENERATOR_YIELD((id)[path stringByAppendingPathComponent: subpath]);
        }
    }
    GENERATOR_END
}

void AppendByte(NSMutableData *data, char byte)
{
    [data appendBytes: &byte length: 1];
}

NSString *SafeUTF8String(NSData *data)
{
    NSString *str = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    if(!str)
        str = [[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding];
    if(!str)
        str = [[NSString alloc] initWithData: data encoding: NSMacOSRomanStringEncoding];
    return str;
}

GENERATOR(int, HTTPParser(void (^responseCallback)(NSString *), void (^headerCallback)(NSDictionary *), void (^bodyCallback)(NSData *), void (^errorCallback)(NSString *)), (int byte))
{
    NSMutableData *responseData = [NSMutableData data];
    
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    __block NSMutableData *currentHeaderData = nil;
    
    NSMutableData *bodyData = [NSMutableData data];
    
    GENERATOR_BEGIN(char byte)
    {
        while(byte != '\r')
        {
            AppendByte(responseData, byte);
            GENERATOR_YIELD(0);
        }
        responseCallback(SafeUTF8String(responseData));
        GENERATOR_YIELD(0); // eat the \r
        if(byte != '\n')
            errorCallback(@"bad CRLF after response line");
        GENERATOR_YIELD(0); // eat the \n
        
        while(1)
        {
            currentHeaderData = [[NSMutableData alloc] init];
            while(byte != '\r')
            {
                AppendByte(currentHeaderData, byte);
                GENERATOR_YIELD(0);
            }
            GENERATOR_YIELD(0);
            if(byte != '\n')
                errorCallback(@"bad CRLF after header line");
            GENERATOR_YIELD(0); // eat the \n
            
            NSString *headerString = SafeUTF8String(currentHeaderData);
            if([headerString length])
            {
                NSUInteger colonLoc = [headerString rangeOfString: @": "].location;
                if(colonLoc == NSNotFound)
                    errorCallback(@"No colon found in header line");
                [headers setObject: [headerString substringFromIndex: colonLoc + 2] forKey: [headerString substringToIndex: colonLoc]];
            }
            else
                break;
        }
        headerCallback(headers);
        
        while(byte != -1)
        {
            AppendByte(bodyData, byte);
            GENERATOR_YIELD(0);
        }
        bodyCallback(bodyData);
    }
    GENERATOR_CLEANUP
    {
        [currentHeaderData release];
    }
    GENERATOR_END
}

void TestHTTP(void)
{
    NSInputStream *is;
    NSOutputStream *os;
    [NSStream getStreamsToHost: [NSHost hostWithName: @"www.google.com"] port: 80 inputStream: &is outputStream: &os];
    
    [is open];
    [os open];
    
    char *writeBytes = "GET / HTTP/1.0\r\n\r\n";
    NSInteger toWrite = strlen(writeBytes);
    while(toWrite)
    {
        NSInteger written = [os write: (uint8_t *)writeBytes maxLength: toWrite];
        if(written < 0)
        {
            perror("write");
            exit(1);
        }
        toWrite -= written;
        writeBytes += written;
    }
    
    int (^parser)(int) = HTTPParser(
                                     ^(NSString *response) {
                                         NSLog(@"Got response: %@", response);
                                     },
                                     ^(NSDictionary *headers) {
                                         NSLog(@"Got headers: %@", headers);
                                     },
                                     ^(NSData *body) {
                                         NSLog(@"Got %ld bytes of body", (long)[body length]);
                                     },
                                     ^(NSString *error) {
                                         NSLog(@"Got error %@", error);
                                     });
    
    uint8_t byte;
    NSInteger amt;
    while((amt = [is read: &byte maxLength: 1]))
    {
        if(amt < 0)
        {
            perror("read");
            exit(1);
        }
        parser(byte);
    }
    parser(-1);
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    int (^primes)(void) = Primes();
    for(int i = 0; i < 10; i++)
        NSLog(@"%d", primes());
    
    NSArray *(^builder)(id) = ArrayBuilder();
    NSLog(@"%@", builder(@"hello"));
    NSLog(@"%@", builder(@"world"));
    NSLog(@"%@", builder(@"how"));
    NSLog(@"%@", builder(@"are"));
    NSLog(@"%@", builder(@"you?"));
    
    NSString *(^wordParser)(unichar ch) = WordParser();
    NSLog(@"%@", wordParser('h'));
    NSLog(@"%@", wordParser('e'));
    NSLog(@"%@", wordParser('l'));
    NSLog(@"%@", wordParser('l'));
    NSLog(@"%@", wordParser('o'));
    NSLog(@"%@", wordParser(' '));
    NSLog(@"%@", wordParser('w'));
    NSLog(@"%@", wordParser('o'));
    NSLog(@"%@", wordParser('r'));
    NSLog(@"%@", wordParser('l'));
    NSLog(@"%@", wordParser('d'));
    NSLog(@"%@", wordParser('!'));
    NSLog(@"%@", wordParser(0));
    
    int (^counter)(void) = Counter(5, 10);
    for(int i = 0; i < 10; i++)
        NSLog(@"%d", counter());
    
    int i = 0;
    for(NSString *path in MAGeneratorEnumerator(FileFinder(@"/Applications", @"app")))
    {
        NSLog(@"%@", path);
        if(++i >= 10)
            break;
    }
    
    [pool release];
    
    return 0;
}
