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
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\.{0,1})([0-9\\*]*)(\\(.+\\))*(\\[[0-9a-z]+\\]){0,1}$" options:NSRegularExpressionCaseInsensitive error:&error];
  
  __block XCUIElement *currentElement = self;
  
  [tokens enumerateObjectsUsingBlock:^(NSString *token, NSUInteger tokenIdx, BOOL *stopTokenEnum) {
    
    NSArray *matches = [regex matchesInString:token
                                      options:NSMatchingAnchored
                                        range:NSMakeRange(0, [token length])];
    NSTextCheckingResult *regRes = [matches objectAtIndex:0];
    NSInteger count = [regRes numberOfRanges];
    NSRange childCharRange = [regRes rangeAtIndex:1];
    NSRange typeRange = [regRes rangeAtIndex:2];
    NSString *childChar = [token substringWithRange:childCharRange];
    NSString *type = [token substringWithRange:typeRange];
    NSInteger elementType ;
    XCUIElementQuery *query;
    if ([type isEqualToString:@"*"]) {
      elementType = XCUIElementTypeAny;
    } else {
      elementType = [type intValue];
    }
    if ([childChar isEqualToString:@"."]) {
      query = [currentElement childrenMatchingType:elementType];
    } else {
      query = [currentElement descendantsMatchingType:elementType];
    }
    Boolean hasCondition = false;
    NSRange condTypeRange;
    NSRange valueRange;
    NSString *condType;
    NSString *value;
    Boolean hasIndex = false;
    NSRange indexRange;
    NSString *index;
    for (NSInteger i = 3; i < count; i++) {
      NSRange optionRange = [regRes rangeAtIndex:i];
      if (optionRange.length == 0) {
        continue;
      }
      NSString *option = [token substringWithRange:optionRange];
      NSError *errorCond = nil;
      NSRegularExpression *regexCondition = [NSRegularExpression regularExpressionWithPattern:@"\\((.*)=(.*)\\)" options:NSRegularExpressionCaseInsensitive error:&errorCond];
      NSArray *conditionMatches = [regexCondition matchesInString:option
                                                          options:NSMatchingAnchored
                                                            range:NSMakeRange(0, [option length])];
      if ([conditionMatches count] > 0) {
        NSTextCheckingResult *regConditionRes = [conditionMatches objectAtIndex:0];
        NSInteger condCount = [regConditionRes numberOfRanges];
        if (condCount > 0) {
          hasCondition = true;
          condTypeRange = [regConditionRes rangeAtIndex:1];
          valueRange = [regConditionRes rangeAtIndex:2];
          condType = [option substringWithRange:condTypeRange];
          value = [option substringWithRange:valueRange];
          continue;
        }
      }
      NSError *errorInd = nil;
      NSRegularExpression *regexIndex = [NSRegularExpression regularExpressionWithPattern:@"\\[(.*)\\]" options:NSRegularExpressionCaseInsensitive error:&errorInd];
      NSArray *indexMatches = [regexIndex matchesInString:option
                                                  options:NSMatchingAnchored
                                                    range:NSMakeRange(0, [option length])];
      if ([indexMatches count] > 0) {
        NSTextCheckingResult *regIndexRes = [indexMatches objectAtIndex:0];
        NSInteger indexCount = [regIndexRes numberOfRanges];
        if (indexCount > 0) {
          hasIndex = true;
          indexRange = [regIndexRes rangeAtIndex:1];
          index = [option substringWithRange:indexRange];
        }
      }
    }
    Boolean isArray = false;
    NSArray *array;
    if (hasCondition) {
      if ([condType isEqualToString:@"id"]) {
        query = [query matchingIdentifier:value];
      } else {
        array = [currentElement fb_descendantsMatchingProperty:condType value:value partialSearch:false];
        if ([array count] == 0) {
          query = [currentElement childrenMatchingType:XCUIElementTypeOther];
        } else {
          isArray = true;
        }
      }
    }
    if (hasIndex) {
      if (isArray) {
        if ([index isEqualToString:@"last"]) {
          currentElement = [array lastObject];
        } else {
          currentElement = array[[index intValue]];
        }
      } else {
        if ([index isEqualToString:@"last"]) {
          currentElement = [[query allElementsBoundByIndex] lastObject];
        } else {
          currentElement = [query elementBoundByIndex:[index intValue]];
        }
      }
    } else {
      if (isArray) {
        currentElement = array[0];
      } else {
        currentElement = [query elementBoundByIndex:0];
      }
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
