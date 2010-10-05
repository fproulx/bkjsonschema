//
//  CoreDataJsonSchemaExporter.h
//  BkCoreData2JsonSchema
//
//  BkCoreData2JsonSchema is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  BkCoreData2JsonSchema is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with BkCoreData2JsonSchema.  If not, see <http://www.gnu.org/licenses/>.
//
//  Created by François Proulx on 18/08/10.
//  Copyright 2010 Backelite. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString * const BkCoreDataModelExporterErrorDomain;
extern NSUInteger const BkCoreDataModelExporterUnknownPropertyIdentifier;
extern NSUInteger const BkCoreDataModelExporterUnsupportedAttributeTypeErrorCode;

@interface BKCoreDataModelExporter : NSObject {
@private
	NSManagedObjectModel *model;
}

- (id) initWithModelFilePath:(NSString *)aFilePath;
- (NSString *) exportJsonSchemaRepresentationWithClassNamePrefix:(NSString *)aClassPrefix nullSafeParser:(BOOL)isNullSafeParser error:(NSError **)anError;

@end
