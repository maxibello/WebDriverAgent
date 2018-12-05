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

#pragma mark - Search by Xui
- (NSArray<XCUIElement *> *)av_descendantsMatchingXui:(NSString *)locator
{
  // Делим локатор по вертикальной черте на элементы.
  NSMutableArray *resultElementList = [NSMutableArray array];
  NSArray *tokens = [self av_parseLocator:locator];
  NSError *error = nil;
  // Создаем регулярку для парсинга одной части локатора.
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\.{0,1})([0-9\\*]*)(\\(.+\\))*(\\[[0-9a-z]+\\]){0,1}$" options:NSRegularExpressionCaseInsensitive error:&error];
  __block XCUIElement *currentElement = self;
  // Цикл обходит все элементы локатора.
  [tokens enumerateObjectsUsingBlock:^(NSString *token, NSUInteger tokenIdx, BOOL *stopTokenEnum) {
    NSTextCheckingResult *regRes = [self av_parsePartOfLocator:regex locator:token];
    XCUIElementQuery *query = [self av_getQueryByType:regRes locator:token element:currentElement];
    currentElement = [self av_getElement:regRes locator:token query:query];
  }];
  [resultElementList addObject:currentElement];
  return resultElementList.copy;
}
- (NSArray *)av_parseLocator:(NSString *)locator {
  return  [locator componentsSeparatedByString:@"|"];
}
- (NSTextCheckingResult *)av_parsePartOfLocator:(NSRegularExpression *)regex locator: (NSString *)locator {
  NSArray *matches = [regex matchesInString:locator
                                    options:NSMatchingAnchored
                                      range:NSMakeRange(0, [locator length])];
  if ([matches count] == 0) {
    NSString *message = [NSString stringWithFormat: @"Bad part of locator: %@", locator];
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:message userInfo:nil];
  }
  return [matches objectAtIndex:0];
}
-(XCUIElementQuery *)av_getQueryByType:(NSTextCheckingResult *)regRes locator: (NSString *)locator element: (XCUIElement *)element {
  // Получаем признак того нужен ли нам потомок или ребенок.
  NSRange childCharRange = [regRes rangeAtIndex:1];
  NSString *childChar = [locator substringWithRange:childCharRange];
  // Получаем тип запрашеваемого элемента.
  NSRange typeRange = [regRes rangeAtIndex:2];
  NSString *type = [locator substringWithRange:typeRange];
  NSInteger elementType ;
  XCUIElementQuery *query;
  // Если тип указан как звездочка, значит берем любой элемент, если указан пробрасываем его.
  if ([type isEqualToString:@"*"]) {
    elementType = XCUIElementTypeAny;
  } else {
    elementType = [type intValue];
  }
  // Если в начале стоит точка, то мы берем ребенка, если нет, то потомка.
  if ([childChar isEqualToString:@"."]) {
    query = [element childrenMatchingType:elementType];
  } else {
    query = [element descendantsMatchingType:elementType];
  }
  return query;
}
- (XCUIElement *)av_getElement:(NSTextCheckingResult *)regRes
                       locator:(NSString *)locator
                         query:(XCUIElementQuery *)query
{
  // Инициализируем переменные для условия.
  Boolean hasPredicate = false;
  NSString *predicate;
  // Инициализируем переменные для индекса.
  Boolean hasIndex = false;
  NSString *index;
  // Получае количество совпандений в строки по регулярному вырожению.
  NSInteger countMatches = [regRes numberOfRanges];
  // В цикле перебераем оставшиеся части локатора элемента.
  for (NSInteger i = 3; i < countMatches; i++) {
    NSRange optionRange = [regRes rangeAtIndex:i];
    // Если совпадение присутствует в массиве, но пустое, то идем дальше
    if (optionRange.length == 0) {
      continue;
    }
    // Получем строку совпадения.
    NSString *option = [locator substringWithRange:optionRange];
    // Проверяем является ли часть локатора элемента условием с помощью regex, если является сохраняем информацию
    // в перменные и переходим к следующей итерации.
    NSError *errorCond = nil;
    NSRegularExpression *regexCondition = [NSRegularExpression regularExpressionWithPattern:@"\\((.*)\\)" options:NSRegularExpressionCaseInsensitive error:&errorCond];
    NSArray *predicateMatches = [regexCondition matchesInString:option
                                                        options:NSMatchingAnchored
                                                          range:NSMakeRange(0, [option length])];
    if ([predicateMatches count] > 0) {
      NSTextCheckingResult *regConditionRes = [predicateMatches objectAtIndex:0];
      NSInteger condCount = [regConditionRes numberOfRanges];
      if (condCount > 0) {
        hasPredicate = true;
        NSRange predicateRange = [regConditionRes rangeAtIndex:1];
        predicate = [option substringWithRange:predicateRange];
        continue;
      }
    }
    // Проверяем является ли часть локатора элемента индексом с помощью regex, если является сохраняем информацию
    // в перменные.
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
        NSRange indexRange = [regIndexRes rangeAtIndex:1];
        index = [option substringWithRange:indexRange];
      }
    }
  }
  // Применение условий к запросу элемента
  if (hasPredicate) {
    if ([predicate hasPrefix:@"id"]) {
      NSArray *explodeResult = [predicate componentsSeparatedByString:@"="];
      query = [query matchingIdentifier:explodeResult[1]];
    } else {
      NSPredicate *predicateObj = [NSPredicate predicateWithFormat:predicate];
      query = [query matchingPredicate:predicateObj];
    }
  }
  // Применяем индекс к запросу или к массиву. Если индекс не указан, то берем первый элемент.
  XCUIElement *element;
  if (hasIndex) {
    if ([index isEqualToString:@"last"]) {
      element = [[query allElementsBoundByIndex] lastObject];
    } else {
      element = [query elementBoundByIndex:[index intValue]];
    }
  } else {
    element = [query elementBoundByIndex:0];
  }
  return element;
}

@end
