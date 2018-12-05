/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */


#import "XCUIElement+FBFind.h"

#import "FBMacros.h"
#import "FBElementTypeTransformer.h"
#import "FBPredicate.h"
#import "NSPredicate+FBFormat.h"
#import "XCElementSnapshot.h"
#import "XCElementSnapshot+FBHelpers.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBWebDriverAttributes.h"
#import "FBElementUtils.h"
#import "FBXCodeCompatibility.h"

@implementation XCUIElement (FBFind)

+ (NSArray<XCUIElement *> *)fb_extractMatchingElementsFromQuery:(XCUIElementQuery *)query shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  if (!shouldReturnAfterFirstMatch) {
    return query.allElementsBoundByIndex;
  }
  XCUIElement *matchedElement = query.fb_firstMatch;
  return matchedElement ? @[matchedElement] : @[];
}


#pragma mark - Search by ClassName

- (NSArray<XCUIElement *> *)fb_descendantsMatchingClassName:(NSString *)className shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSMutableArray *result = [NSMutableArray array];
  XCUIElementType type = [FBElementTypeTransformer elementTypeWithTypeName:className];
  if (self.elementType == type || type == XCUIElementTypeAny) {
    [result addObject:self];
    if (shouldReturnAfterFirstMatch) {
      return result.copy;
    }
  }
  XCUIElementQuery *query = [self descendantsMatchingType:type];
  [result addObjectsFromArray:[self.class fb_extractMatchingElementsFromQuery:query shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch]];
  return result.copy;
}



#pragma mark - Search by CellByIndex

- (NSArray<XCUIElement *> *)fb_descendantsMatchingXui:(NSString *)locator
{
  NSMutableArray *resultElementList = [NSMutableArray array];
  NSArray *tokens = [locator componentsSeparatedByString:@"|"];
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(getBy.*)\\((.+)\\)" options:NSRegularExpressionCaseInsensitive error:&error];
  
  __block XCUIElement *currentElement = self;
  
  [tokens enumerateObjectsUsingBlock:^(NSString *token, NSUInteger tokenIdx, BOOL *stopTokenEnum) {
    
    NSArray *matches = [regex matchesInString:token
                                      options:NSMatchingAnchored
                                        range:NSMakeRange(0, [token length])];
    NSTextCheckingResult *regRes = [matches objectAtIndex:0];
    NSRange funcRange = [regRes rangeAtIndex:1];
    NSRange argRange = [regRes rangeAtIndex:2];
    NSString *func = [token substringWithRange:funcRange];
    NSString *arg = [token substringWithRange:argRange];
    if ([func isEqualToString:@"getById"]) {
      currentElement = [[currentElement fb_descendantsMatchingIdentifier:arg] firstObject];
    } else if ([func isEqualToString:@"getByIndex"]) {
      NSArray *asdf = [arg componentsSeparatedByString:@","];
      NSUInteger type = [[asdf objectAtIndex:0] integerValue];
      NSString *val = [asdf objectAtIndex:1];
      if ([val isEqualToString:@"last"]) {
        currentElement = [[[currentElement descendantsMatchingType:type] allElementsBoundByIndex] lastObject];
      } else {
        NSUInteger indx = [[asdf objectAtIndex:1] integerValue];
        currentElement = [[currentElement descendantsMatchingType:type] elementBoundByIndex:indx];
      }
    } else if ([func isEqualToString:@"getByAttribute"]) {
      NSArray *asdf = [arg componentsSeparatedByString:@","];
      NSString *attrName = [asdf objectAtIndex:0];
      NSString *attrValue = [asdf objectAtIndex:1];
      currentElement = [[currentElement fb_descendantsMatchingProperty:attrName value:attrValue partialSearch:false] firstObject];
    }
  }];
  
  [resultElementList addObject:currentElement];
  return resultElementList.copy;
}


#pragma mark - Search by property value

- (NSArray<XCUIElement *> *)fb_descendantsMatchingProperty:(NSString *)property value:(NSString *)value partialSearch:(BOOL)partialSearch
{
  NSMutableArray *elements = [NSMutableArray array];
  [self descendantsWithProperty:property value:value partial:partialSearch results:elements];
  return elements;
}

- (void)descendantsWithProperty:(NSString *)property value:(NSString *)value partial:(BOOL)partialSearch results:(NSMutableArray<XCUIElement *> *)results
{
  if (partialSearch) {
    NSString *text = [self fb_valueForWDAttributeName:property];
    BOOL isString = [text isKindOfClass:[NSString class]];
    if (isString && [text rangeOfString:value].location != NSNotFound) {
      [results addObject:self];
    }
  } else {
    if ([[self fb_valueForWDAttributeName:property] isEqual:value]) {
      [results addObject:self];
    }
  }

  property = [FBElementUtils wdAttributeNameForAttributeName:property];
  value = [value stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
  NSString *operation = partialSearch ?
  [NSString stringWithFormat:@"%@ like '*%@*'", property, value] :
  [NSString stringWithFormat:@"%@ == '%@'", property, value];

  NSPredicate *predicate = [FBPredicate predicateWithFormat:operation];
  XCUIElementQuery *query = [[self descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:predicate];
  NSArray *childElements = [query allElementsBoundByIndex];
  [results addObjectsFromArray:childElements];
}


#pragma mark - Search by Predicate String

- (NSArray<XCUIElement *> *)fb_descendantsMatchingPredicate:(NSPredicate *)predicate shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSPredicate *formattedPredicate = [NSPredicate fb_formatSearchPredicate:predicate];
  NSMutableArray<XCUIElement *> *result = [NSMutableArray array];
  // Include self element into predicate search
  if ([formattedPredicate evaluateWithObject:self.fb_lastSnapshot]) {
    if (shouldReturnAfterFirstMatch) {
      return @[self];
    }
    [result addObject:self];
  }
  XCUIElementQuery *query = [[self descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:formattedPredicate];
  [result addObjectsFromArray:[self.class fb_extractMatchingElementsFromQuery:query shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch]];
  return result.copy;
}


#pragma mark - Search by xpath

- (NSArray<XCElementSnapshot *> *)getMatchedSnapshotsByXPathQuery:(NSString *)xpathQuery
{
  // XPath will try to match elements only class name, so requesting elements by XCUIElementTypeAny will not work. We should use '*' instead.
  xpathQuery = [xpathQuery stringByReplacingOccurrencesOfString:@"XCUIElementTypeAny" withString:@"*"];
  [self fb_waitUntilSnapshotIsStable];
  return [self.fb_lastSnapshot fb_descendantsMatchingXPathQuery:xpathQuery];
}

- (NSArray<XCUIElement *> *)fb_descendantsMatchingXPathQuery:(NSString *)xpathQuery shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSArray *matchingSnapshots = [self getMatchedSnapshotsByXPathQuery:xpathQuery];
  if (0 == [matchingSnapshots count]) {
    return @[];
  }
  if (shouldReturnAfterFirstMatch) {
    XCElementSnapshot *snapshot = matchingSnapshots.firstObject;
    matchingSnapshots = @[snapshot];
  }
  return [self fb_filterDescendantsWithSnapshots:matchingSnapshots];
}


#pragma mark - Search by Accessibility Id

- (NSArray<XCUIElement *> *)fb_descendantsMatchingIdentifier:(NSString *)accessibilityId shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSMutableArray *result = [NSMutableArray array];
  if (self.identifier == accessibilityId) {
    [result addObject:self];
    if (shouldReturnAfterFirstMatch) {
      return result.copy;
    }
  }
  XCUIElementQuery *query = [[self descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:accessibilityId];
  [result addObjectsFromArray:[self.class fb_extractMatchingElementsFromQuery:query shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch]];
  return result.copy;
}

@end
