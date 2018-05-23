#import <WMF/NSString+WMFHTMLParsing.h>
#import <hpple/TFHpple.h>
#import <WMF/NSString+WMFExtras.h>
#import <WMF/WMF-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const MWKSectionShareSnippetXPath = @"/html/body/p[not(.//span[@id='coordinates'])][1]//text()";

@interface MWKSection ()

@property (readwrite, weak, nonatomic) MWKArticle *article;

@property (readwrite, copy, nonatomic, nullable) NSNumber *toclevel; // optional
@property (readwrite, copy, nonatomic, nullable) NSNumber *level;    // optional; string in JSON, but seems to be number-safe?
@property (readwrite, copy, nonatomic, nullable) NSString *line;     // optional; HTML
@property (readwrite, copy, nonatomic, nullable) NSString *number;   // optional; can be "1.2.3"
@property (readwrite, copy, nonatomic, nullable) NSString *index;    // optional; can be "T-3" for transcluded sections
@property (readwrite, strong, nonatomic, nullable) NSURL *fromURL;   // optional
@property (readwrite, copy, nonatomic, nullable) NSString *anchor;   // optional
@property (readwrite, assign, nonatomic) int sectionId;              // required; -> id
@property (readwrite, assign, nonatomic) BOOL references;            // optional; marked by presence of key with empty string in JSON

@property (readwrite, copy, nonatomic, nullable) NSString *text; // may be nil

@property (readwrite, weak, nonatomic, nullable) MWKSection *parent;
@property (readwrite, strong, nonatomic, nullable) NSMutableArray *mutableChildren;

@end

@implementation MWKSection

- (instancetype)initWithArticle:(MWKArticle *)article dict:(NSDictionary *)dict {
    self = [self initWithURL:article.url];
    if (self) {
        self.article = article;

        self.toclevel = [self optionalNumber:@"toclevel" dict:dict];
        self.level = [self optionalNumber:@"level" dict:dict]; // may be a numeric string
        self.line = [self optionalString:@"line" dict:dict];
        self.number = [self optionalString:@"number" dict:dict]; // deceptively named, this must be a string
        self.index = [self optionalString:@"index" dict:dict];   // deceptively named, this must be a string

        if ([dict[@"fromtitle"] length] > 0) {
            self.fromURL = [self.url wmf_URLWithTitle:dict[@"fromtitle"]];
        }
        self.anchor = [self optionalString:@"anchor" dict:dict];
        self.sectionId = [[self requiredNumber:@"id" dict:dict] intValue];
        self.references = ([self optionalString:@"references" dict:dict] != nil);

        // Not present in .plist, loaded separately there
        self.text = [self optionalString:@"text" dict:dict];

        self.mutableChildren = [NSMutableArray new];
    }
    return self;
}

- (id)dataExport {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    if (self.toclevel) {
        dict[@"toclevel"] = self.toclevel;
    }
    if (self.level) {
        dict[@"level"] = self.level;
    }
    if (self.line) {
        dict[@"line"] = self.line;
    }
    if (self.number) {
        dict[@"number"] = self.number;
    }
    if (self.index) {
        dict[@"index"] = self.index;
    }
    if (self.fromURL) {
        dict[@"fromtitle"] = self.fromURL.wmf_title;
    }
    if (self.anchor) {
        dict[@"anchor"] = self.anchor;
    }
    dict[@"id"] = @(self.sectionId);
    if (self.references) {
        dict[@"references"] = @"";
    }
    // Note: text is stored separately on disk
    return [NSDictionary dictionaryWithDictionary:dict];
}

- (BOOL)isLeadSection {
    return (self.sectionId == 0);
}

- (nullable NSURL *)sourceURL {
    if (self.fromURL) {
        // We probably came from a foreign template section!
        return self.fromURL;
    } else {
        return self.url;
    }
}

- (BOOL)hasTextData {
    return [self.article.dataStore hasHTMLFileForSection:self];
}

- (nullable NSString *)text {
    if (_text == nil) {
        _text = [self.article.dataStore sectionTextWithId:self.sectionId article:self.article];
    }
    return _text;
}

- (BOOL)save:(NSError **)outError {
    NSError *internalError = nil;
    [self.article.dataStore saveSection:self error:&internalError];
    if (internalError) {
        if (outError) {
            *outError = internalError;
        }
        return NO;
    }
    if (_text != nil) {
        return [self.article.dataStore saveSectionText:_text section:self error:outError];
    } else {
        return YES;
    }
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    } else if ([object isKindOfClass:[MWKSection class]]) {
        return [self isEqualToSection:object];
    } else {
        return NO;
    }
}

- (BOOL)isEqualToSection:(MWKSection *)section {
    return WMF_IS_EQUAL(self.url, section.url) && self.sectionId == section.sectionId && self.references == section.references && WMF_EQUAL(self.toclevel, isEqualToNumber:, section.toclevel) && WMF_EQUAL(self.level, isEqualToNumber:, section.level) && WMF_EQUAL(self.line, isEqualToString:, section.line) && WMF_EQUAL(self.number, isEqualToString:, section.number) && WMF_EQUAL(self.index, isEqualToString:, section.index) && WMF_EQUAL(self.fromURL, isEqual:, section.fromURL) && WMF_EQUAL(self.anchor, isEqualToString:, section.anchor) && WMF_EQUAL(self.text, isEqualToString:, section.text);
}

- (NSString *)description {
    //Do not use MTLModel's description as it will cause recursion since this instance has a reference to the article, which also has a reference to this section section
    return [NSString stringWithFormat:@"section id: %d line: %@ level: %@", self.sectionId, self.line, self.level];
}

#pragma mark - Extraction

- (NSString *)shareSnippet {
    return [[self textForXPath:MWKSectionShareSnippetXPath] wmf_shareSnippetFromText];
}

- (NSString *)textForXPath:(NSString *)xpath {
    NSArray *xpathResults = [self elementsInTextMatchingXPath:xpath];
    if (xpathResults.count) {
        return [[xpathResults valueForKey:WMF_SAFE_KEYPATH([TFHppleElement new], raw)] componentsJoinedByString:@""];
    }
    return @"";
}

- (nullable NSArray *)elementsInTextMatchingXPath:(NSString *)xpath {
    NSParameterAssert(xpath.length);
    if (!self.text) {
        DDLogWarn(@"Trying to query section text before downloaded. Section: %@", self);
        return nil;
    }
    return [[TFHpple hppleWithHTMLData:[self.text dataUsingEncoding:NSUTF8StringEncoding]] searchWithXPathQuery:xpath];
}

#pragma mark - Section Hierarchy

- (nullable MWKSection *)parentSection {
    return self.parent;
}

- (MWKSection *)rootSection {
    MWKSection *parent = self.parent;
    if (!parent) {
        return self;
    }
    return [self.parent rootSection];
}

- (BOOL)isChildOfSection:(MWKSection *)section {
    return [self.parent isEqualToSection:section];
}

- (BOOL)isDecendantOfSection:(MWKSection *)section {
    MWKSection *parent = self.parent;
    if (!parent) {
        return NO;
    }
    if ([parent isEqualToSection:self.parent]) {
        return YES;
    }
    return [self.parent isDecendantOfSection:section];
}

- (BOOL)sectionHasSameRootSection:(MWKSection *)section {
    return [[self rootSection] isEqualToSection:[section rootSection]];
}

- (nullable NSArray *)children {
    return _mutableChildren;
}

- (void)addChild:(MWKSection *)child {
    NSParameterAssert(child.level);
    NSAssert([child.level compare:self.level] == NSOrderedDescending,
             @"Illegal attempt to add %@ to sibling or descendant %@.", child, self);
    [self.mutableChildren addObject:child];
    child.parent = self;
}

- (void)removeAllChildren {
    [self.mutableChildren removeAllObjects];
}

// XPath selector which gets a pretty good summary (without html!).
// Grabs text from first paragraph which has children and text from
// elements after that. Huge benefit by not requiring separate html
// stripping step!
static NSString *const WMFSectionSummaryXPathSelector = @"\
(\
   //p[count(*) > 0 and not(ancestor::table)]/descendant-or-self::*\
   |\
   //p[count(*) > 0 and not(ancestor::table)]/following::*\
)\
[\
   not(@id = 'coordinates')\
   and\
   not(ancestor::table or ancestor::*[\
       @id = 'coordinates'\
       or\
       @class = 'IPA'\
       or\
       starts-with(@class, 'IPA ')\
       or\
       contains(@class, ' IPA ')\
   ])\
]\
/text()";

- (nullable NSString *)summary {
    NSArray *textNodes = [self elementsInTextMatchingXPath:WMFSectionSummaryXPathSelector];
    if (!textNodes || !textNodes.count) {
        return nil;
    }
    return [[[textNodes wmf_map:^id(TFHppleElement *node) {
        return node.raw;
    }] componentsJoinedByString:@" "] wmf_summaryFromText];
}

@end

NS_ASSUME_NONNULL_END
