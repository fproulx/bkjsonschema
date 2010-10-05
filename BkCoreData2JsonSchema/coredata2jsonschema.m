//
//  coredata2jsonschema.m
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
//  Created by François Proulx on 17/08/10.
//  Copyright Backelite 2010 . All rights reserved.
//

#import <objc/objc-auto.h>

#import "BKCoreDataModelExporter.h"

int main (int argc, const char * argv[]) 
{	
    objc_startCollectorThread();
	
	NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
	NSString *modelFilePath = [args stringForKey:@"model"]; // The only mandatory argument
	
	if (modelFilePath) {
		BKCoreDataModelExporter *exporter = [[BKCoreDataModelExporter alloc] initWithModelFilePath:modelFilePath];
		if (exporter) {
			NSError *error = nil;
			// By default, generate NSNull-safe parser code
			BOOL isNullSafeParser = ([args stringForKey:@"nullSafeParser"] ? [args boolForKey:@"nullSafeParser"] : YES);
			NSString *jsonRepresentation = [exporter exportJsonSchemaRepresentationWithClassNamePrefix:[args stringForKey:@"classNamePrefix"] nullSafeParser:isNullSafeParser error:&error];
			if (jsonRepresentation) {
				fprintf(stdout, "%s\n", [jsonRepresentation UTF8String]);
				return 0;
			} else {
				if (error) {
					fprintf(stderr, "Export failed with error:\n%s\n", [[error localizedDescription] UTF8String]);
				}
				return 1;
			}
		} else {
			fprintf(stderr, "Unable to initialize CoreData model exporter with model object file\nMake sure to point to a compiled MOM (.mom file).");
			return 1;
		}
	} else {
		fprintf(stderr, "Usage: %s [-classNamePrefix <class-name-prefix>] [-nullSafeParser <YES>|<NO>] -model <core-data-model-file>\n", [[[NSProcessInfo processInfo] processName] UTF8String]);
		return 1;
	}
}

