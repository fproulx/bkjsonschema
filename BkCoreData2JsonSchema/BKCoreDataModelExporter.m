//
//  CoreDataModelExporter.m
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

#import "BKCoreDataModelExporter.h"

#import "JSON.h"

NSString * const BkCoreDataModelExporterErrorDomain = @"BkCoreDataModelExporterErrorDomain";
NSUInteger const BkCoreDataModelExporterUnknownPropertyIdentifier = 1000;
NSUInteger const BkCoreDataModelExporterUnsupportedAttributeTypeErrorCode = 1001;

@interface BKCoreDataModelExporter ()

@property (retain) NSManagedObjectModel *model;

@end

@implementation BKCoreDataModelExporter

@synthesize model;

- (id) initWithModelFilePath:(NSString *)aFilePath
{
	if ((self = [super init])) {
		NSURL *modelFileUrl = [NSURL fileURLWithPath:aFilePath];
		
		// If the file given is not a compiled MOM, we need to compile it ourselves and store it in a temp file
		if (![[modelFileUrl pathExtension] isEqualToString:@"mom"]) {
			NSString *momc = @"/Developer/usr/bin/momc";
			NSString *tempFile = [[NSTemporaryDirectory() stringByAppendingPathComponent:[(id)CFUUIDCreateString(kCFAllocatorDefault, CFUUIDCreate(kCFAllocatorDefault)) autorelease]] stringByAppendingPathExtension:@"mom"];
			system([[NSString stringWithFormat:@"\"%@\" \"%@\" \"%@\"", momc, aFilePath, tempFile] UTF8String]);
			modelFileUrl = [NSURL fileURLWithPath:tempFile];
		}
		
		if (!(self.model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelFileUrl])) {
			return nil;
		}
	}
	return self;
}

#pragma mark -
#pragma mark Utility methods

- (NSString *) schemaObjectIdentifierOfEntityDescription:(NSEntityDescription *)anEntityDescription
{
	// Get the most specific identifier for the object in the schema (either the entity name itself or a different remote name)
	NSString *objectIdentifier = [[anEntityDescription userInfo] objectForKey:@"remote"];
	return (objectIdentifier ? objectIdentifier : [anEntityDescription name]);
}

- (NSDictionary *) parentTypeReferenceForEntityDescription:(NSEntityDescription *)anEntityDescription
{
	NSDictionary *reference = nil;
	NSEntityDescription *parentEntity = [anEntityDescription superentity];
	if (parentEntity) {
		NSString *parentEntityObjectIdentifier = [self schemaObjectIdentifierOfEntityDescription:parentEntity];
		if (parentEntityObjectIdentifier) {
			reference = [[NSDictionary alloc] initWithObjectsAndKeys:parentEntityObjectIdentifier, @"$ref", nil];
		}
	}
	return reference;
}

- (NSString *) schemaTypeNameForPropertyDescription:(NSPropertyDescription *)aPropertyDescription metadata:(NSString **)someMetadata error:(NSError **)anError
{
	NSString *propertyType = nil;
	if ([aPropertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
		NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *) aPropertyDescription;
		if ([relationshipDescription isToMany]) {
			propertyType = @"array"; // One-to-many relationship
		} else {
			propertyType = @"object"; // One-to-one relationship
		}
	} else if ([aPropertyDescription isKindOfClass:[NSAttributeDescription class]]) {
		NSAttributeType attributeType = [((NSAttributeDescription *) aPropertyDescription) attributeType];
		switch (attributeType) {
			case NSInteger16AttributeType:
			case NSInteger32AttributeType:
			case NSInteger64AttributeType:
				propertyType = @"number"; // In order not to lose precision, store all number as NSNumber (the JSON parser will use the proper cluster class variant)
				if (someMetadata) {
					*someMetadata = @"Integer attribute type";
				}
				break;
			case NSDecimalAttributeType:
			case NSDoubleAttributeType:
			case NSFloatAttributeType:
				propertyType = @"number"; // In order not to lose precision, store all number as NSNumber (the JSON parser will use the proper cluster class variant)
				if (someMetadata) {
					*someMetadata = @"Floating point attribute type";
				}
				break;
			case NSBooleanAttributeType:
				propertyType = @"boolean";
				if (someMetadata) {
					*someMetadata = @"Boolean attribute type";
				}
				break;
			case NSStringAttributeType:
				propertyType = @"string";
				break;
			case NSDateAttributeType:
				propertyType = @"date-time"; // This will assume ISO8601 datetime format, unless a typeQualifier is specified
				break;
			case NSTransformableAttributeType:
				propertyType = @"object";
				if (someMetadata) {
					*someMetadata = @"Transformable attribute type";
				}
				break;
			case NSUndefinedAttributeType:
			case NSBinaryDataAttributeType:
			case NSObjectIDAttributeType:
			default:
				if (anError) {
					NSString *errorMessage = [[NSString alloc] initWithFormat:@"Unsupported attribute type (%u) for property description named (%@)", attributeType, [aPropertyDescription name]];
					NSDictionary *errorUserInfo = [[NSDictionary alloc] initWithObjectsAndKeys:errorMessage, NSLocalizedDescriptionKey, nil];
					*anError = [NSError errorWithDomain:BkCoreDataModelExporterErrorDomain 
												   code:BkCoreDataModelExporterUnsupportedAttributeTypeErrorCode 
											   userInfo:errorUserInfo];
				}
				break;
		}
	}
	return propertyType;
}

- (NSString *) schemaPropertyNameForPropertyDescription:(NSPropertyDescription *)aPropertyDescription
{
	NSString *propertyName = [[aPropertyDescription userInfo] objectForKey:@"remote"];
	return (propertyName ? propertyName : [aPropertyDescription name]);
}

#pragma mark -

- (NSString *) exportJsonSchemaRepresentationWithClassNamePrefix:(NSString *)aClassPrefix nullSafeParser:(BOOL)isNullSafeParser error:(NSError **)anError
{
	// These data structures will contain the objects specification for the JSON schema (as NSArray form)
	NSMutableSet *objectIdentifiersSet = [[NSMutableSet alloc] init];
	NSMutableArray *objectsList = [[NSMutableArray alloc] init];
	
	for (NSEntityDescription *entityDescription in [model entities]) {
		// Get the most specific schema object identifier available
		NSString *objectIdentifier = [self schemaObjectIdentifierOfEntityDescription:entityDescription];
		
		// Skip object that have already been added to the schema
		if (![objectIdentifiersSet containsObject:objectIdentifier]) {
			// Gather all metadata for this object
			NSMutableDictionary *objectDict = [[NSMutableDictionary alloc] init];
			[objectDict setObject:@"object" forKey:@"type"]; // Root objects always have the "object" type
			[objectDict setObject:objectIdentifier forKey:@"id"]; // The object id in the schema
			[objectDict setObject:[entityDescription managedObjectClassName] forKey:@"mappedType"]; // The name of the Obj-C to generate
			NSDictionary *superclassReference = [self parentTypeReferenceForEntityDescription:entityDescription];
			if (superclassReference) {
				[objectDict setObject:superclassReference forKey:@"extends"]; // Add superclass reference, if needed
			}
			
			// remove properties herited from super entity
			NSMutableDictionary *entityProperties = [[entityDescription propertiesByName] mutableCopy];
			[entityProperties removeObjectsForKeys:[[[entityDescription superentity] propertiesByName] allKeys]];
			// For each property declared in the model, add it to the schema
			NSMutableDictionary *objectProperties = [[NSMutableDictionary alloc] init];
			for (NSPropertyDescription *propertyDescription in [entityProperties allValues]) {
				NSString *propertyIdentifier = [self schemaPropertyNameForPropertyDescription:propertyDescription];
				if (propertyIdentifier) {
					NSMutableDictionary *objectProperty = [[NSMutableDictionary alloc] init];
					
					NSError *propertyTypeMappingError = nil;
					NSString *propertyMetadata = nil;
					NSString *propertyType = [self schemaTypeNameForPropertyDescription:propertyDescription 
																			   metadata:&propertyMetadata 
																				  error:&propertyTypeMappingError];
					if (propertyType) {
						[objectProperty setObject:propertyType forKey:@"type"];
						[objectProperty setObject:[propertyDescription name] forKey:@"mappedProperty"];
						if (isNullSafeParser) {
							// jsonschema2objc defaults to NSNull-unsafe code, by default it recommended to generate NSNull-safe parser code for Core Data
							[objectProperty setObject:[NSNumber numberWithBool:NO] forKey:@"propertyCanBeNullObject"];
						}
						if (propertyMetadata) {
							[objectProperty setObject:propertyMetadata forKey:@"description"];
						}
						
						// Add proper relationship mapping as needed
						if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
							NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *) propertyDescription;
							NSEntityDescription *relationshipDestinationEntity = [relationshipDescription destinationEntity];
							NSString *relationshipItemIdentifier = [self schemaObjectIdentifierOfEntityDescription:relationshipDestinationEntity];
							if (relationshipItemIdentifier) {
								if ([relationshipDescription isToMany]) {
									// Describe one to many relationship using ref'd entity
									NSDictionary *relationshipDict = [[NSDictionary alloc] initWithObjectsAndKeys:relationshipItemIdentifier, @"$ref", nil];
									[objectProperty setObject:relationshipDict forKey:@"items"];
								} else {
									// Describe one to one relationship using ref'd entity
									[objectProperty setObject:[relationshipDestinationEntity managedObjectClassName] forKey:@"mappedType"];
								}
								
								// If the destination entity of the relationship is abstract, 
								// we'll use a local type resolver to figure out the proper entity class to use when parsing
								if ([relationshipDestinationEntity isAbstract]) {
									[objectProperty setObject:[NSString stringWithFormat:@"%@LocalTypeResolver", aClassPrefix] forKey:@"typeResolver"];
								}
							} else {
								// Fail fast and return the type mapping error
								if (anError) {
									NSString *errorMessage = [[NSString alloc] initWithFormat:@"Unknown schema identifier for items in relationship (%@) of entity (%@)", [propertyDescription name], [entityDescription name]];
									NSDictionary *errorUserInfo = [[NSDictionary alloc] initWithObjectsAndKeys:errorMessage, NSLocalizedDescriptionKey, nil];
									*anError = [NSError errorWithDomain:BkCoreDataModelExporterErrorDomain 
																   code:BkCoreDataModelExporterUnknownPropertyIdentifier 
															   userInfo:errorUserInfo];
								}
								return nil;
							}
						}
						
						[objectProperties setObject:objectProperty forKey:propertyIdentifier];
					} else {
						// Fail fast and return the type mapping error
						if (anError) {
							*anError = propertyTypeMappingError;
						}
						return nil;
					}
				} else {
					// Fail fast
					if (anError) {
						NSString *errorMessage = [[NSString alloc] initWithFormat:@"Unknown property identifier (%@) for entity (%@)", propertyIdentifier, [entityDescription name]];
						NSDictionary *errorUserInfo = [[NSDictionary alloc] initWithObjectsAndKeys:errorMessage, NSLocalizedDescriptionKey, nil];
						*anError = [NSError errorWithDomain:BkCoreDataModelExporterErrorDomain 
													   code:BkCoreDataModelExporterUnknownPropertyIdentifier 
												   userInfo:errorUserInfo];
					}
					return nil;
				}
			}
			[objectDict setObject:objectProperties forKey:@"properties"];
			
			// Add the object definition to the schema
			[objectIdentifiersSet addObject:objectIdentifier];
			[objectsList addObject:objectDict];
		}
	}

	NSError *outputError = nil;
	SBJsonWriter *jsonWriter = [[SBJsonWriter alloc] init];
	jsonWriter.humanReadable = YES;
	NSString *jsonOutput = [jsonWriter stringWithObject:objectsList error:&outputError];
	
	return jsonOutput;
}

@end
