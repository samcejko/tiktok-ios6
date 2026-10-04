#import "TKModels.h"
#import "TKCommon.h"

@implementation TKVideo

+ (instancetype)videoFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    TKVideo *v = [[TKVideo alloc] init];
    v.videoId = TKStr(json[@"id"]);
    if (!v.videoId.length) return nil;
    v.author = TKStr(json[@"author"]);
    v.authorName = TKStr(json[@"authorName"]) ?: v.author;
    v.desc = TKStr(json[@"desc"]) ?: @"";
    v.coverURL = TKStr(json[@"cover"]);
    v.webURL = TKStr(json[@"url"]);
    v.music = TKStr(json[@"music"]);
    v.likes = TKInt(json[@"likes"]);
    v.commentCount = TKInt(json[@"comments"]);
    v.plays = TKInt(json[@"plays"]);
    v.durationSeconds = TKInt(json[@"duration"]);
    v.width = TKInt(json[@"width"]);
    v.height = TKInt(json[@"height"]);
    v.category = TKInt(json[@"category"]);
    NSMutableArray *tags = [NSMutableArray array];
    for (id t in TKArr(json[@"tags"])) { NSString *s = [TKStr(t) lowercaseString]; if (s.length && ![tags containsObject:s]) [tags addObject:s]; }
    v.tags = tags.count ? tags : [self hashtagsInText:v.desc];
    v.musicId = TKStr(json[@"musicId"]);
    v.musicOriginal = TKBool(json[@"musicOriginal"]);
    v.lang = TKStr(json[@"lang"]);
    v.playURL = TKStr(json[@"playUrl"]);
    if ([json[@"headers"] isKindOfClass:[NSDictionary class]]) v.playHeaders = json[@"headers"];
    return v;
}

// #words of a caption, for sources that do not list the hashtags separately
+ (NSArray *)hashtagsInText:(NSString *)text
{
    NSMutableArray *out = [NSMutableArray array];
    if (!text.length) return out;
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"#([\\w]+)" options:0 error:NULL];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *tag = [[text substringWithRange:[m rangeAtIndex:1]] lowercaseString];
        if (tag.length && ![out containsObject:tag]) [out addObject:tag];
    }
    return out;
}

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.videoId ?: @"";
    if (self.author) d[@"author"] = self.author;
    if (self.authorName) d[@"authorName"] = self.authorName;
    if (self.desc) d[@"desc"] = self.desc;
    if (self.coverURL) d[@"cover"] = self.coverURL;
    if (self.webURL) d[@"url"] = self.webURL;
    if (self.music) d[@"music"] = self.music;
    d[@"likes"] = @(self.likes);
    d[@"comments"] = @(self.commentCount);
    d[@"plays"] = @(self.plays);
    d[@"duration"] = @(self.durationSeconds);
    d[@"width"] = @(self.width);
    d[@"height"] = @(self.height);
    if (self.category) d[@"category"] = @(self.category);
    if (self.tags.count) d[@"tags"] = self.tags;
    if (self.musicId.length) d[@"musicId"] = self.musicId;
    d[@"musicOriginal"] = @(self.musicOriginal);
    if (self.lang.length) d[@"lang"] = self.lang;
    return d;
}

- (NSString *)shareURL
{
    if (self.webURL.length) return self.webURL;
    if (self.author.length && self.videoId.length) return [NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@", self.author, self.videoId];
    return [NSString stringWithFormat:@"https://www.tiktok.com/@_/video/%@", self.videoId ?: @""];
}

@end

@implementation TKComment

+ (instancetype)commentFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    TKComment *c = [[TKComment alloc] init];
    c.author = TKStr(json[@"author"]) ?: @"";
    c.text = TKStr(json[@"text"]) ?: @"";
    c.likes = TKInt(json[@"likes"]);
    return c;
}

@end
