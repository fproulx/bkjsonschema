#!/usr/bin/env ruby
# jsonschema2objc.rb
# Author: Francois Proulx
# Author: Philippe Bernery
# Copyright 2010 Backelite. All rights reserved.
#
# jsonschema2objc is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# jsonschema2objc is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with jsonschema2objc.  If not, see <http://www.gnu.org/licenses/>.
#
# usage: ./jsonschema2objc.rb [arguments]
#
# Arguments:
#
# -h, --help:
#    show help
#
# -o, --output-directory [directory]:
#    The directory where the Objective-C header / implementation files will be generated
#
# -s, --schema [json-schema-file]:
#    The JSON schema describing the mapping between Web services and model objects
#    Optionally, you can provide the JSON schema through STDIN
#
# --coredata:
#    Generate Core Data compatible code instead
#
# --overwrite:
#    Overwrite any previously generated files


require 'rubygems'
require 'json'
require 'json/ext'
require 'pp'
require 'set'
require 'tmpdir'
require 'getoptlong'
require 'rdoc/usage'
require 'fcntl'

## Set it to true to user nonNullObjectForKey: instead of objectForKey: everywhere in the generated code
$forceNonNullObjects = false

##
## Global const values
##
$objCBaseClass = "NSObject"
$coreDataBaseClass = "NSManagedObject"

# JSON Schema standard types
$schemaTypeToObjCTypeMap = Hash.new
$schemaTypeToObjCTypeMap["array"] = "NSArray *"
$schemaTypeToObjCTypeMap["string"] = "NSString *"
$schemaTypeToObjCTypeMap["number"] = "NSNumber *"
$schemaTypeToObjCTypeMap["integer"] = "NSInteger "
$schemaTypeToObjCTypeMap["date-time"] = "NSDate *"
$schemaTypeToObjCTypeMap["date"] = "NSDate *"
$schemaTypeToObjCTypeMap["boolean"] = "BOOL "
# Non standard JSON Schema types
$schemaTypeToObjCTypeMap["map"] = "NSDictionary *"
$schemaTypeToObjCTypeMap["unsigned-integer"] = "NSUInteger "

# JSON Schema standard types for Core Data generation
$schemaTypeToCoreDataTypeMap = Hash.new
$schemaTypeToCoreDataTypeMap["array"] = "NSSet *"
$schemaTypeToCoreDataTypeMap["string"] = "NSString *"
$schemaTypeToCoreDataTypeMap["number"] = "NSNumber *"
$schemaTypeToCoreDataTypeMap["date-time"] = "NSDate *"
$schemaTypeToCoreDataTypeMap["date"] = "NSDate *"
$schemaTypeToCoreDataTypeMap["boolean"] = "NSNumber *"

$assignStorageTypes = Set.new
$assignStorageTypes.add("NSInteger ")
$assignStorageTypes.add("NSUInteger ")
$assignStorageTypes.add("BOOL ")

$generationDateString = Time.now.localtime.strftime("%Y-%m-%d")

$bkCommonTypes = Set.new
$bkCommonTypes.add("BkISO8601DurationConverter") # Legacy type converter
$bkCommonTypes.add("BkISO8601DurationValueTransformer")

##
## Methods section
##
class SortedSet
  def addClassToImplement(className)
    if not $bkCommonTypes.include?(className)
      self.add(className)
    end
  end
end

def baseObjectClass()
  if $coredata
    return $coreDataBaseClass;
  else
    return $objCBaseClass
  end
end

def schemaTypeToObjcType(jsonSchemaType)
  if $coredata
    return $schemaTypeToCoreDataTypeMap[jsonSchemaType]
  else
    return $schemaTypeToObjCTypeMap[jsonSchemaType]
  end
end

def mappedTypeForObjectDefinition(objectId, objectDefinition)
  if objectDefinition.nil?
    STDERR.puts "mappedTypeForObjectDefinition: Unknown object definition in #{objectId}"
    exit 1
  else
    result = objectDefinition["mappedType"]
    if not result
      result = objectDefinition["id"]
    end
    return result
  end
end

def fileHeaderForFilename(filename)
  result = String.new
  result << "//\n"
  result <<  "//\t#{filename}\n"
  result << "//\t\n"
  result << "//\tCreated by jsonschema2objc.\n"
  result << "//\tCopyright 2010 Backelite. All rights reserved.\n"
  result << "//\n\n"
  return result
end

def applyDiffOrOverwriteFile(filename, tempFilename)
  fileNameOutput = "%s/%s" % [$outputDirectory, filename]
  fileNameOriginalOutput = "%s/%s" % [$originalOutputDirectory, filename]

  if $overwrite == false and File.exist?(fileNameOutput)
    ret = `diff3 -m "#{fileNameOutput}" "#{fileNameOriginalOutput}" "#{tempFilename}" > "#$tempFile"; mv "#$tempFile" "#{fileNameOutput}"`
    puts ">>>> Diff for #{filename} --> #{ret}"
    
    # Update original files
    FileUtils.cp(tempFilename, fileNameOriginalOutput)
  else
    # Copy new output and keep original file
    FileUtils.cp(tempFilename, fileNameOutput)
    FileUtils.cp(tempFilename, fileNameOriginalOutput)
  end
end

def generateEnumFiles(objectId, objectDefinition)
  # Figure out the output Objective C enum name
  mappedType = mappedTypeForObjectDefinition(objectId, objectDefinition)
  
  puts "Generating file for enum #{mappedType}"
  
  headerFileLines = String.new
  implFileLines = String.new
  
  enumValues = objectDefinition["values"]
  if enumValues and not enumValues.empty?
    headerFileLines << "typedef enum {\n"
    
    implFileLines << "#import \"#{mappedType}.h\"\n\n"
    implFileLines << "NSString *#{mappedType}ToString(#{mappedType} value)\n{\n"
    implFileLines << "\tNSString *result = nil;\n\n"
    implFileLines << "\tswitch(value) {\n"
    
    # Generate all enum values
    index = 0
    count = enumValues.count
    
    enumValues.each do | map |
      key = map.keys[0]
      value = map.values[0]
      
      fullKey = mappedType + key
      
      # Add proper line feed
      if index < (count - 1)
        headerFileLines << "\t#{fullKey} = #{value},\n"
      else
        headerFileLines << "\t#{fullKey} = #{value}\n"
      end
      
      implFileLines << "\t\tcase #{fullKey}:\n"
      implFileLines << "\t\t\tresult = @\"#{value}:#{fullKey}\";\n"
      implFileLines << "\t\t\tbreak;\n"
      
      index += 1
    end

    headerFileLines << "} #{mappedType};\n\n"
    
    # Enum to string function
    headerFileLines << "NSString *#{mappedType}ToString(#{mappedType} value);\n"

    implFileLines << "\t\tdefault:\n"
    implFileLines << "\t\t\tresult = @\"<value not in enum>\";\n"
    implFileLines << "\t\t\tbreak;\n"

    implFileLines << "\t}\n\n"
    implFileLines << "\treturn result;\n}"
  end

  # Generate enum header file
  objectEnumHeaderFileNameTemp = "%s/%s.h" % [$tempDirectory, mappedType]
  objectEnumHeaderFile = File.new(objectEnumHeaderFileNameTemp, "w")
  objectEnumHeaderFile.puts(fileHeaderForFilename("#{mappedType}.h"))
  objectEnumHeaderFile.puts(headerFileLines)
  objectEnumHeaderFile.close

  applyDiffOrOverwriteFile("#{mappedType}.h", objectEnumHeaderFileNameTemp)
  
  # Generate enum impl file
  objectEnumImplFileNameTemp = "%s/%s.m" % [$tempDirectory, mappedType]
  objectEnumImplFile = File.new(objectEnumImplFileNameTemp, "w")
  objectEnumImplFile.puts(fileHeaderForFilename("#{mappedType}.m"))
  objectEnumImplFile.puts(implFileLines)
  objectEnumImplFile.close

  applyDiffOrOverwriteFile("#{mappedType}.m", objectEnumImplFileNameTemp)
end

def generateClassFiles(objectId, objectDefinition)
  # Figure out the output Objective C class name
  mappedType = mappedTypeForObjectDefinition(objectId, objectDefinition)
  
  puts "Generating header file for class #{mappedType}"
  objectHeaderFileNameTemp = "%s/%s.h" % [$tempDirectory, mappedType]
  objectHeaderFile = File.new(objectHeaderFileNameTemp, "w")
  
  iVarsDeclarations = String.new
  propertiesDeclarations = String.new
  coreDataGeneratedAccessors = String.new
  referencedClassesForwardDeclarations = SortedSet.new
  properties = objectDefinition["properties"]
  referencedClassesDependencies = SortedSet.new
  
  # Figure out the parent class name
  extends = objectDefinition["extends"]
  parentMappedType = baseObjectClass()
  if extends
    typeReference = extends["$ref"]
    if typeReference
      referencedType = $schemaIndex[typeReference]
      if referencedType
        parentMappedType = mappedTypeForObjectDefinition(objectId, referencedType)
        # Add parent class dep
        referencedClassesDependencies.add(parentMappedType)
      else
        STDERR.puts "!!! Unknown referenced type #{typeReference}"
        exit 1
      end
    else
      STDERR.puts "!!! Missing $ref in #{objectId}"
      exit 1
    end
  end
  
  # Generate header file header
  objectHeaderFile.puts(fileHeaderForFilename("#{mappedType}.h"))
  
  # Add #import declaration for parent class
  if $coredata
    objectHeaderFile.puts "#import <CoreData/CoreData.h>\n"  
  else
    objectHeaderFile.puts "#import <Foundation/Foundation.h>\n"  
  end
  
  # Generate ivars and properties declarations in header file
  properties.sort.each do | property |
    propertyName = property[0]
    propertyDefinition = property[1]
    
    # Get most specific name for the current property
    propertyMappedName = propertyDefinition["mappedProperty"]
    propertyMappedName ||= propertyName
    
    # Get most specific type for current property
    propertyType = propertyDefinition["type"]
    propertyMappedType = propertyDefinition["mappedType"]
    propertyMappedType ||= baseObjectClass()
    rawObjcType = schemaTypeToObjcType(propertyType)
    
    if propertyType == "object"
      # Any type declared as object is considered to derive from NSObject, so we retain them
      rawObjcType ||= propertyMappedType + " *"
      if not propertyMappedType == baseObjectClass()
        referencedClassesForwardDeclarations.add(propertyMappedType)
      end
    end

    # Override with provided type
    objcType = String.new
    if not propertyDefinition["mappedType"].nil? and (propertyType == "integer" or propertyType == "unsigned-integer")
      objcType = propertyDefinition["mappedType"] + " "
      referencedClassesDependencies.add(propertyDefinition["mappedType"])
    else
      objcType = rawObjcType
    end
    
    # Figure out which type storage to use
    if $coredata
      propertyStorageType = "retain"
    else
      propertyStorageType = $assignStorageTypes.include?(rawObjcType) ? "assign" : "retain"
    end
    
    # Accumulate ivar declaration
    if propertyType == "array"
      arrayPropertyDefinition = propertyDefinition["items"]
      arrayPropertyItemsType = schemaTypeToObjcType(arrayPropertyDefinition["type"])
      arrayPropertyItemsTypeRef = arrayPropertyDefinition["$ref"]
      
      if arrayPropertyItemsType
        if $coredata
          STDERR.puts "!!! Illegal state for Core Data code generation"
          exit 1
        end
        
        propertiesDeclarations << "@property (nonatomic, #{propertyStorageType}) #{objcType}#{propertyMappedName}; // List of (#{arrayPropertyItemsType}) objects\n"
      elsif arrayPropertyItemsTypeRef
        # Figure out the actual type of the objects stored in the array
        referencedType = $schemaIndex[arrayPropertyItemsTypeRef]
        if referencedType
          innerLoopPropertyMappedType = mappedTypeForObjectDefinition(objectId, referencedType)
          propertiesDeclarations << "@property (nonatomic, #{propertyStorageType}) #{objcType}#{propertyMappedName}; // List of (#{innerLoopPropertyMappedType} *) objects\n"
          
          if $coredata
            referencedClassesForwardDeclarations.add(innerLoopPropertyMappedType)
            
            # Add method declarations for dynamic Core Data relationship accessors
            capitalizedPropertyMappedName = propertyMappedName.gsub(/^[a-z]|\s+[a-z]/) { |a| a.upcase }
            coreDataGeneratedAccessors << "- (void) add#{capitalizedPropertyMappedName}Object:(#{innerLoopPropertyMappedType} *)value;\n"
            coreDataGeneratedAccessors << "- (void) remove#{capitalizedPropertyMappedName}Object:(#{innerLoopPropertyMappedType} *)value;\n"
            coreDataGeneratedAccessors << "- (void) add#{capitalizedPropertyMappedName}:(NSSet *)value;\n"
            coreDataGeneratedAccessors << "- (void) remove#{capitalizedPropertyMappedName}:(NSSet *)value;\n\n"
          end
        else
          STDERR.puts "!!! Unknown referenced type #{arrayPropertyItemsTypeRef}"
          exit 1
        end
      else
        STDERR.puts "!!! Array property is missing metadata"
        exit 1
      end
    else
      propertiesDeclarations << "@property (nonatomic, #{propertyStorageType}) #{objcType}#{propertyMappedName};\n"
    end
    
    iVarsDeclarations << "\t#{objcType}#{propertyMappedName};\n"
  end
  
  # Add class deps
  referencedClassesDependencies.each do | depClass | 
    objectHeaderFile.puts "#import \"#{depClass}.h\"\n"
  end
  
  objectHeaderFile.puts "\n"
  
  # Add forward declarations for used classes
  referencedClassesForwardDeclarations.each do | forwardDeclClass | 
    objectHeaderFile.puts "@class #{forwardDeclClass};\n"
  end
  
  # Assemble final header file contents
  if extends or $coredata
    objectHeaderFile.puts "\n@interface #{mappedType} : #{parentMappedType} {\n"
  else
    objectHeaderFile.puts "\n@interface #{mappedType} : #{parentMappedType} <NSCoding, NSCopying> {\n"
    objectHeaderFile.puts iVarsDeclarations
  end
  objectHeaderFile.puts "}\n\n"
  objectHeaderFile.puts propertiesDeclarations
  if $coredata
    objectHeaderFile.puts "\n+ (NSEntityDescription *) entityForClassInManagedObjectContext:(NSManagedObjectContext *)moc;\n\n"
    objectHeaderFile.puts "- (id) initWithDictionary:(NSDictionary *)dict inManagedObjectContext:(NSManagedObjectContext *)moc;\n"
  else
    objectHeaderFile.puts "\n- (id) initWithDictionary:(NSDictionary *)dict;\n"
  end
  objectHeaderFile.puts "- (NSDictionary *) dictionaryRepresentation;\n"
  objectHeaderFile.puts "- (NSString *) JSONRepresentation;\n\n"
  objectHeaderFile.puts "@end\n"
  
  if $coredata
    objectHeaderFile.puts "\n@interface #{mappedType} (JsonSchema2ObjcGeneratedAccessors)\n\n"
    objectHeaderFile.puts coreDataGeneratedAccessors
    objectHeaderFile.puts "@end\n"
  end

  objectHeaderFile.close
  
  puts "Generating implementation file for class #{mappedType}"
  objectImplFileNameTemp = "%s/%s.m" % [$tempDirectory, mappedType]
  objectImplFile = File.new(objectImplFileNameTemp, "w")
  
  # Generate implementation file header
  objectImplFile.puts(fileHeaderForFilename("#{mappedType}.m"))
  
  # Add #import declaration for class header
  objectImplFile.puts "#import \"#{mappedType}.h\"\n\n"
  
  # Accumulate other references classes as we initialize properties
  generatedCodeReferencedClasses = SortedSet.new
  generatedCodeReferencedClasses.merge(referencedClassesForwardDeclarations)
  
  # Accumulate references to type resolvers
  typeResolverClasses = SortedSet.new
  
  # Accumulate references to type converters
  typeConverterClasses = SortedSet.new
  
  # Properties loop accumulators
  automaticPropertyImplLines = String.new
  deallocLines = String.new
  parserLines = String.new
  
  # Other parser generator state vars
  parserUsesTemporaryRawVariable = false
  parserUsesTemporaryInitVariable = false
  
  # Initialize dict exporter code generation
  dictExporterLines = String.new
  
  # Init NSCoding code generation
  decoderLines = String.new
  encoderLines = String.new
  
  # Init NSCopying code generation
  copyLines = String.new
  
  properties.sort.each do | property |
    propertyName = property[0]
    propertyDefinition = property[1]
    
    # Get most specific name for the current property
    propertyMappedName = propertyDefinition["mappedProperty"]
    propertyMappedName ||= propertyName
    
    if $coredata
      automaticPropertyImplLines << "@dynamic #{propertyMappedName};\n"
    else
      automaticPropertyImplLines << "@synthesize #{propertyMappedName};\n"
    end
    
    # Get most specific type for current property
    propertyType = propertyDefinition["type"]
    propertyTypeQualifier = propertyDefinition["typeQualifier"]
    propertyMappedType = propertyDefinition["mappedType"]
    propertyMappedType ||= propertyType
    rawObjcType = schemaTypeToObjcType(propertyType)

    # Debug
    puts " --> Mapping #{propertyName} to #{propertyMappedName} with type #{rawObjcType}"
    
    # Generate dealloc only for retained properties
    if not $assignStorageTypes.include?(rawObjcType)
      deallocLines << "\tself.#{propertyMappedName} = nil;\n"
    end
    
    # Generate parser and exporter code
    objectForKeyMethod = "objectForKey:"
    propertyCanBeNullObject = true
    if propertyDefinition.has_key?("propertyCanBeNullObject") or $forceNonNullObjects
      propertyCanBeNullObject = propertyDefinition["propertyCanBeNullObject"]
      if not propertyCanBeNullObject or $forceNonNullObjects
        objectForKeyMethod = "nonNullObjectForKey:"
        puts " ---> propertyCanBeNullObject : #{propertyCanBeNullObject}"
     end
    end
    
    propertyTypeConverter = propertyDefinition["typeConverter"]
    if propertyTypeConverter and not propertyTypeConverter.empty?
      puts "---> Will use type converter #{propertyTypeConverter} to map to actual class"
      typeConverterClasses.addClassToImplement(propertyTypeConverter)
      
      if $coredata
        parserLines << "\t\tself.#{propertyMappedName} = [#{propertyTypeConverter} convertedObjectFromString:[dict #{objectForKeyMethod}@\"#{propertyName}\"]];"
      else
        parserLines << "\t\t#{propertyMappedName} = [[#{propertyTypeConverter} convertedObjectFromString:[dict #{objectForKeyMethod}@\"#{propertyName}\"]] retain];\n"        
      end
      
      dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
      dictExporterLines << "\t\t[bufferDict setObject:[#{propertyTypeConverter} stringFromConvertedObject:self.#{propertyMappedName}] forKey:@\"#{propertyName}\"];\n"
      dictExporterLines << "\t}\n"
    else
      case propertyType
      when "object"
        parserUsesTemporaryRawVariable = true
        parserLines << "\t\tif ((tempRawPropertyVar = [dict #{objectForKeyMethod}@\"#{propertyName}\"])) {\n"
        
        propertyTypeResolver = propertyDefinition["typeResolver"]
        if propertyTypeResolver and not propertyTypeResolver.empty?
          puts "---> Will use type resolver #{propertyTypeResolver} to map to actual class"
          typeResolverClasses.addClassToImplement(propertyTypeResolver)
          
          if $coredata
            parserUsesTemporaryInitVariable = true    
            parserLines << "\t\t\ttempInitPropertyVar = [[[#{propertyTypeResolver} classForPropertyName:@\"#{propertyName}\" withObject:tempRawPropertyVar] alloc] initWithDictionary:tempRawPropertyVar inManagedObjectContext:moc];\n"
            parserLines << "\t\t\tself.#{propertyMappedName} = tempInitPropertyVar;\n";
            parserLines << "\t\t\t[tempInitPropertyVar release];\n"
          else
            parserLines << "\t\t\t#{propertyMappedName} = [[[#{propertyTypeResolver} classForPropertyName:@\"#{propertyName}\" withObject:tempRawPropertyVar] alloc] initWithDictionary:tempRawPropertyVar];\n"
          end
        else
          puts "---> Will use provided class #{propertyMappedType}"
          
          if $coredata
            parserUsesTemporaryInitVariable = true
            parserLines << "\t\t\ttempInitPropertyVar = [[#{propertyMappedType} alloc] initWithDictionary:tempRawPropertyVar inManagedObjectContext:moc];\n"
            parserLines << "\t\t\tself.#{propertyMappedName} = tempInitPropertyVar;\n";
            parserLines << "\t\t\t[tempInitPropertyVar release];\n"
          else
            parserLines << "\t\t\t#{propertyMappedName} = [[#{propertyMappedType} alloc] initWithDictionary:tempRawPropertyVar];\n"
          end
        end
        
        parserLines << "\t\t}\n"
        
        dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
        dictExporterLines << "\t\t[bufferDict setObject:[self.#{propertyMappedName} dictionaryRepresentation] forKey:@\"#{propertyName}\"];\n"
        dictExporterLines << "\t}\n"
      when "string", "number"
        if $coredata
          parserLines << "\t\tself.#{propertyMappedName} = [dict #{objectForKeyMethod}@\"#{propertyName}\"];\n"
        else
          parserLines << "\t\t#{propertyMappedName} = [[dict #{objectForKeyMethod}@\"#{propertyName}\"] retain];\n"
        end

        dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
        dictExporterLines << "\t\t[bufferDict setObject:self.#{propertyMappedName} forKey:@\"#{propertyName}\"];\n"
        dictExporterLines << "\t}\n"
      when "array"
        arrayPropertyDefinition = propertyDefinition["items"]
        arrayPropertyItemsType = arrayPropertyDefinition["type"]
        arrayPropertyItemsTypeQualifier = arrayPropertyDefinition["typeQualifier"]
        arrayPropertyItemsTypeRef = arrayPropertyDefinition["$ref"]
        
        # Can the items contained in this array be null objects
        arrayPropertyItemCanBeNullObject = true
        if arrayPropertyDefinition.has_key?("itemCanBeNullObject")
          tempVal = propertyDefinition["propertyCanBeNullObject"]
          if not tempVal 
            arrayPropertyItemCanBeNullObject = false
            puts "\n\n** itemCanBeNullObject : #{arrayPropertyItemCanBeNullObject}\n\n"
         end
        end
          
        # Create temporary variable name for this list property
        innerLoopListVariableName = "json" + propertyMappedName.capitalize + "List"

        if arrayPropertyItemsType
          # BEGIN Check if property value is provided before trying to create an empty array
          parserLines << "\t\tid #{innerLoopListVariableName} = [dict #{objectForKeyMethod}@\"#{propertyName}\"];\n"
          parserLines << "\t\tif(#{innerLoopListVariableName}) {\n"
          
          # Create inner loop to insert values contained in the list
          innerLoopVariableName = "json" + propertyMappedName.capitalize + "Element"
          innerLoopBufferVariableName = propertyMappedName + "Buffer"
          if $coredata
            parserLines << "\t\t\tNSMutableSet *#{innerLoopBufferVariableName} = [[NSMutableSet alloc] init];\n"
          else
            parserLines << "\t\t\tNSMutableArray *#{innerLoopBufferVariableName} = [[NSMutableArray alloc] init];\n"
          end
          parserLines << "\t\t\tfor (id #{innerLoopVariableName} in #{innerLoopListVariableName}) {\n"
          
          case arrayPropertyItemsType
          when "date", "date-time", "time"
            genericDateFormatterName = "ISO8601DateFormatterWithoutFractionalSeconds"
            # Try to get a date formatter that better suits the expected format
            case arrayPropertyItemsType
            when "date"
              genericDateFormatterName = "ISO8601SimpleDateFormatter"
            when "date-time"
              # Support type qualifier specializing the date-time zone (facilitating the proper choice of data parser)
              case arrayPropertyItemsTypeQualifier
              when "implicit-timezone"
                genericDateFormatterName = "ISO8601DateFormatterWithImplicitTimeZone"
              else
                genericDateFormatterName = "ISO8601DateFormatterWithoutFractionalSeconds"
              end
            end
            
            # Convert strings to date
            generatedCodeReferencedClasses.add("BkDateFormatter")
            parserLines << "\t\t\t\t[#{innerLoopBufferVariableName} addObject:[[BkDateFormatter #{genericDateFormatterName}] dateFromString:#{innerLoopVariableName}]];\n"
        
            # Convert date as strings for export
            dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
            dictExporterLines << "\t\tNSMutableArray *innerList = [[NSMutableArray alloc] init];\n"
            dictExporterLines << "\t\tfor (NSDate *innerLoopDate in self.#{propertyMappedName}) {\n"
            dictExporterLines << "\t\t\t[innerList addObject:[[BkDateFormatter #{genericDateFormatterName}] stringFromDate:innerObject]];\n"
            dictExporterLines << "\t\t}\n"
            dictExporterLines << "\t\t[bufferDict setObject:innerList forKey:@\"#{propertyName}\"];\n"
            dictExporterLines << "\t\t[innerList release];\n"
            dictExporterLines << "\t}\n"
          else
            parserLines << "\t\t\t\t[#{innerLoopBufferVariableName} addObject:#{innerLoopVariableName}];\n"
        
            # Simply inject the array in the buffer as it SHOULD contain simple data types (not custom objects)
            # In this case, an array with "object" items will be exported as a map, "$ref" MUST be used to export complex objects
            dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
            dictExporterLines << "\t\t[bufferDict setObject:self.#{propertyMappedName} forKey:@\"#{propertyName}\"];\n"
            dictExporterLines << "\t}\n"
          end
          
          # Close inner loop to insert values contained in the list
          parserLines << "\t\t\t}\n"
          if $coredata
            parserLines << "\t\t\tself.#{propertyMappedName} = #{innerLoopBufferVariableName};\n"
          else
            parserLines << "\t\t\t#{propertyMappedName} = [[NSArray alloc] initWithArray:#{innerLoopBufferVariableName}];\n"
          end
          parserLines << "\t\t\t[#{innerLoopBufferVariableName} release];\n"
          
          # END Check if property value is provided before trying to create an empty array
          parserLines << "\t\t}\n"
          
        elsif arrayPropertyItemsTypeRef
          referencedType = $schemaIndex[arrayPropertyItemsTypeRef]
          if referencedType
            # BEGIN Check if property value is provided before trying to create an empty array
            parserLines << "\t\tid #{innerLoopListVariableName} = [dict #{objectForKeyMethod}@\"#{propertyName}\"];\n"
            parserLines << "\t\tif(#{innerLoopListVariableName}) {\n"
            
            innerLoopVariableName = "json" + propertyMappedName.capitalize + "Element"
            innerLoopBufferVariableName = propertyMappedName + "Buffer"
            if $coredata
              parserLines << "\t\t\tNSMutableSet *#{innerLoopBufferVariableName} = [[NSMutableSet alloc] init];\n"
            else
              parserLines << "\t\t\tNSMutableArray *#{innerLoopBufferVariableName} = [[NSMutableArray alloc] init];\n"
            end
            parserLines << "\t\t\tfor (id #{innerLoopVariableName} in #{innerLoopListVariableName}) {\n"

            # Should we use a type resolver to create the items contained in the array ?
            arrayPropertyItemsTypeResolver = propertyDefinition["typeResolver"]
            if arrayPropertyItemsTypeResolver and not arrayPropertyItemsTypeResolver.empty?
              puts "---> (array) Will use type resolver #{arrayPropertyItemsTypeResolver} to map to actual class of items"  
              innerLoopPropertyMappedType = mappedTypeForObjectDefinition(objectId, referencedType)
              if not innerLoopPropertyMappedType
                STDERR.puts "!!! Unknown inner loop mapped type"
                exit 1
              end
              generatedCodeReferencedClasses.add(innerLoopPropertyMappedType)
              typeResolverClasses.addClassToImplement(arrayPropertyItemsTypeResolver)

              innerLoopTempVariableName = "#{propertyMappedName}Element"
              if $coredata
                 parserLines << "\t\t\t\t#{innerLoopPropertyMappedType} *#{innerLoopTempVariableName} = [[[#{arrayPropertyItemsTypeResolver} classForPropertyName:@\"#{propertyName}\" withObject:#{innerLoopVariableName}] alloc] initWithDictionary:#{innerLoopVariableName} inManagedObjectContext:moc];\n"
              else
                parserLines << "\t\t\t\t#{innerLoopPropertyMappedType} *#{innerLoopTempVariableName} = [[[#{arrayPropertyItemsTypeResolver} classForPropertyName:@\"#{propertyName}\" withObject:#{innerLoopVariableName}] alloc] initWithDictionary:#{innerLoopVariableName}];\n"
              end
              if arrayPropertyItemCanBeNullObject
                parserLines << "\t\t\t\tif (#{innerLoopTempVariableName}) {\n"
              else
                # Add check for non-nullness of each item
                parserLines << "\t\t\t\tif (#{innerLoopTempVariableName} && ![#{innerLoopTempVariableName} isKindOfClass:[NSNull class]]) {\n"
              end
              parserLines << "\t\t\t\t\t[#{innerLoopBufferVariableName} addObject:#{innerLoopTempVariableName}];\n"
              parserLines << "\t\t\t\t\t[#{innerLoopTempVariableName} release];\n"
              parserLines << "\t\t\t\t}\n"
              parserLines << "\t\t\t}\n"
            else
              # Figure out the actual type of the objects stored in the array
              innerLoopPropertyMappedType = mappedTypeForObjectDefinition(objectId, referencedType)
              if not innerLoopPropertyMappedType
                STDERR.puts "---> (array) Unknown inner loop mapped type"
                exit 1
              end
              generatedCodeReferencedClasses.add(innerLoopPropertyMappedType)

              puts "---> (array) Will use provided class #{propertyMappedType} for items"

              innerLoopTempVariableName = "#{propertyMappedName}Element"
              if arrayPropertyItemCanBeNullObject
                if $coredata
                  parserLines << "\t\t\t\t#{innerLoopPropertyMappedType} *#{innerLoopTempVariableName} = [[#{innerLoopPropertyMappedType} alloc] initWithDictionary:#{innerLoopVariableName} inManagedObjectContext:moc];\n"
                else
                  parserLines << "\t\t\t\t#{innerLoopPropertyMappedType} *#{innerLoopTempVariableName} = [[#{innerLoopPropertyMappedType} alloc] initWithDictionary:#{innerLoopVariableName}];\n"
                end
                parserLines << "\t\t\t\t[#{innerLoopBufferVariableName} addObject:#{innerLoopTempVariableName}];\n"
                parserLines << "\t\t\t\t[#{innerLoopTempVariableName} release];\n"
              else
                # Add check for non-nullness of each item
                parserLines << "\t\t\t\tif (#{innerLoopVariableName} && ![#{innerLoopVariableName} isKindOfClass:[NSNull class]]) {\n"
                if $coredata
                  parserLines << "\t\t\t\t\t#{innerLoopPropertyMappedType} *#{innerLoopTempVariableName} = [[#{innerLoopPropertyMappedType} alloc] initWithDictionary:#{innerLoopVariableName} inManagedObjectContext:moc];\n"
                else
                  parserLines << "\t\t\t\t\t#{innerLoopPropertyMappedType} *#{innerLoopTempVariableName} = [[#{innerLoopPropertyMappedType} alloc] initWithDictionary:#{innerLoopVariableName}];\n"
                end
                parserLines << "\t\t\t\t\t[#{innerLoopBufferVariableName} addObject:#{innerLoopTempVariableName}];\n"
                parserLines << "\t\t\t\t\t[#{innerLoopTempVariableName} release];\n"
                parserLines << "\t\t\t\t}\n"
              end
              parserLines << "\t\t\t}\n"
            end

            if $coredata
              parserLines << "\t\t\tself.#{propertyMappedName} = #{innerLoopBufferVariableName};\n"
            else
              parserLines << "\t\t\t#{propertyMappedName} = [[NSArray alloc] initWithArray:#{innerLoopBufferVariableName}];\n"
            end
            parserLines << "\t\t\t[#{innerLoopBufferVariableName} release];\n"
            
            # END Check if property value is provided before trying to create an empty array
            parserLines << "\t\t}\n"

            # TODO Finish this
            dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
            dictExporterLines << "\t\tNSMutableArray *innerList = [[NSMutableArray alloc] init];\n"
            dictExporterLines << "\t\tfor (id innerObject in self.#{propertyMappedName}) {\n"
            dictExporterLines << "\t\t\t[innerList addObject:[innerObject dictionaryRepresentation]];\n"
            dictExporterLines << "\t\t}\n"
            dictExporterLines << "\t\t[bufferDict setObject:innerList forKey:@\"#{propertyName}\"];\n"
            dictExporterLines << "\t\t[innerList release];\n"
            dictExporterLines << "\t}\n"
          else
            STDERR.puts "!!! Unknown referenced type #{arrayPropertyItemsTypeRef}"
            exit 1
          end
        else
          STDERR.puts "!!! Invalid array declaration for #{propertyName} in #{mappedType}. It MUST contain a either a \"type\" or a \"$ref\"."
          exit 1
        end
      when "boolean"
        if $coredata
          parserLines << "\t\tself.#{propertyMappedName} = [NSNumber numberWithBool:[[dict #{objectForKeyMethod}@\"#{propertyName}\"] boolValue]];\n"
        else
          parserLines << "\t\t#{propertyMappedName} = [[dict #{objectForKeyMethod}@\"#{propertyName}\"] boolValue];\n"
        end
        
        if $coredata
          dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
          dictExporterLines << "\t\t[bufferDict setObject:[NSNumber numberWithBool:[self.#{propertyMappedName} boolValue]] forKey:@\"#{propertyName}\"];\n"
          dictExporterLines << "\t}\n"
        else
          dictExporterLines << "\t[bufferDict setObject:[NSNumber numberWithBool:#{propertyMappedName}] forKey:@\"#{propertyName}\"];\n"
        end
      when "integer"
        if $coredata
          parserLines << "\t\tself.#{propertyMappedName} = [dict #{objectForKeyMethod}@\"#{propertyName}\"];\n"
        else
          parserLines << "\t\t#{propertyMappedName} = [[dict #{objectForKeyMethod}@\"#{propertyName}\"] integerValue];\n"
        end
        
        if $coredata
          dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
          dictExporterLines << "\t[bufferDict setObject:self.#{propertyMappedName} forKey:@\"#{propertyName}\"];\n"
          dictExporterLines << "\t}\n"
        else
          dictExporterLines << "\t[bufferDict setObject:[NSNumber numberWithInteger:#{propertyMappedName}] forKey:@\"#{propertyName}\"];\n"
        end
      when "unsigned-integer"
        if $coredata
          parserLines << "\t\tself.#{propertyMappedName} = [dict #{objectForKeyMethod}@\"#{propertyName}\"];\n"
        else
          parserLines << "\t\t#{propertyMappedName} = [[dict #{objectForKeyMethod}@\"#{propertyName}\"] unsignedIntegerValue];\n"
        end
      
        if $coredata
          dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
          dictExporterLines << "\t[bufferDict setObject:self.#{propertyMappedName} forKey:@\"#{propertyName}\"];\n"
          dictExporterLines << "\t}\n"
        else
          dictExporterLines << "\t[bufferDict setObject:[NSNumber numberWithUnsignedInteger:#{propertyMappedName}] forKey:@\"#{propertyName}\"];\n"
        end
      when "date", "date-time"
        genericDateFormatterName = "ISO8601DateFormatterWithoutFractionalSeconds"
        # Try to get a date formatter that better suits the expected format
        case propertyType
        when "date"
          genericDateFormatterName = "ISO8601SimpleDateFormatter"
        when "date-time"
          genericDateFormatterName = "ISO8601DateFormatter"
        end
        
        parserUsesTemporaryRawVariable = true
        parserLines << "\t\tif ((tempRawPropertyVar = [dict #{objectForKeyMethod}@\"#{propertyName}\"])) {\n"
        generatedCodeReferencedClasses.add("BkDateFormatter")
        if $coredata
          parserLines << "\t\t\tself.#{propertyMappedName} = [[BkDateFormatter #{genericDateFormatterName}] dateFromString:tempRawPropertyVar];\n"
        else
          parserLines << "\t\t\t#{propertyMappedName} = [[[BkDateFormatter #{genericDateFormatterName}] dateFromString:tempRawPropertyVar] retain];\n"
        end
        parserLines << "\t\t}\n"
    
        dictExporterLines << "\tif (self.#{propertyMappedName}) {\n"
        dictExporterLines << "\t\t[bufferDict setObject:[[BkDateFormatter #{genericDateFormatterName}] stringFromDate:self.#{propertyMappedName}] forKey:@\"#{propertyName}\"];\n"
        dictExporterLines << "\t}\n"
      when "map"
        STDERR.puts "!!! WARNING Unimplemented map type support. Skipping property in #{objectId}"
      else
        STDERR.puts "!!! Unsupported property type #{propertyType} in #{objectId}"
        exit 1
      end
    end
  
    # Generate NSCoding code
    case propertyType
    when "object", "string", "number", "array", "map", "date", "date-time", "time"
      decoderLines << "\t\tself.#{propertyMappedName} = [decoder decodeObjectForKey:@\"#{propertyMappedName}\"];\n"
      encoderLines << "\t[encoder encodeObject:#{propertyMappedName} forKey:@\"#{propertyMappedName}\"];\n"
    when "integer", "unsigned-integer"
      decoderLines << "\t\tself.#{propertyMappedName} = [decoder decodeIntegerForKey:@\"#{propertyMappedName}\"];\n"
      encoderLines << "\t[encoder encodeInteger:#{propertyMappedName} forKey:@\"#{propertyMappedName}\"];\n"
    when "boolean"
      decoderLines << "\t\tself.#{propertyMappedName} = [decoder decodeBoolForKey:@\"#{propertyMappedName}\"];\n"
      encoderLines << "\t[encoder encodeBool:#{propertyMappedName} forKey:@\"#{propertyMappedName}\"];\n"
    else
      STDERR.puts "!!! Unsupported property type for NSCoding #{propertyType} in #{objectId}"
      exit 1
    end
    
    # Generate NSCopying code
    if $assignStorageTypes.include?(rawObjcType)
      copyLines << "\tcopy.#{propertyMappedName} = #{propertyMappedName};\n"
    else
      copyLines << "\tcopy.#{propertyMappedName} = [[#{propertyMappedName} copy] autorelease];\n"
    end
  end
  
  # Add imports for class references
  if not generatedCodeReferencedClasses.empty?
    objectImplFile.puts "// Referenced classes"
    generatedCodeReferencedClasses.each do | classDecl | 
      objectImplFile.puts "#import \"#{classDecl}.h\"\n"
    end
  end
  
  # Type resolvers support
  if not typeResolverClasses.empty?
    objectImplFile.puts "\n// Referenced type resolvers"
    typeResolverClasses.each do | classDecl | 
      # Add imports for type resolvers
      objectImplFile.puts "#import \"#{classDecl}.h\"\n"
      
      # Generate type resolver class files
      puts "Generating header for type resolver class #{classDecl}"
      typeResolverHeaderFileNameTemp = "%s/%s.h" % [$tempDirectory, classDecl]
      typeResolverHeaderFile = File.new(typeResolverHeaderFileNameTemp, "w")

      # Generate type resolver header
      typeResolverHeaderFile.puts(fileHeaderForFilename("#{classDecl}.h"))
      typeResolverHeaderFile.puts "#import <Foundation/Foundation.h>\n\n"
      typeResolverHeaderFile.puts "@interface #{classDecl} : #{$objCBaseClass} {\n"
      typeResolverHeaderFile.puts "}\n\n"
      typeResolverHeaderFile.puts "+ (Class) classForPropertyName:(NSString *)aPropertyName withObject:(NSDictionary *)anObject;\n\n"
      typeResolverHeaderFile.puts "@end\n"
      
      typeResolverHeaderFile.close
      
      puts "Generating implementation for type resolver class #{classDecl}"
      typeResolverImplFileNameTemp = "%s/%s.m" % [$tempDirectory, classDecl]
      typeResolverImplFile = File.new(typeResolverImplFileNameTemp, "w")
      
      # Generate type resolver impl header
      typeResolverImplFile.puts(fileHeaderForFilename("#{classDecl}.m"))
      typeResolverImplFile.puts "#import \"#{classDecl}.h\"\n\n"
      typeResolverImplFile.puts "@implementation #{classDecl}\n\n"
      typeResolverImplFile.puts "+ (Class) classForPropertyName:(NSString *)aPropertyName withObject:(NSDictionary *)anObject\n{\n"
      typeResolverImplFile.puts "\t//TODO: implement this method\n"
      typeResolverImplFile.puts "\treturn nil;\n"
      typeResolverImplFile.puts "}\n\n"
      typeResolverImplFile.puts "@end\n"
      
      typeResolverImplFile.close
      
      applyDiffOrOverwriteFile("#{classDecl}.h", typeResolverHeaderFileNameTemp)
      applyDiffOrOverwriteFile("#{classDecl}.m", typeResolverImplFileNameTemp)
    end
  end
  
  # NSValueTransformer support
  if not typeConverterClasses.empty?
    objectImplFile.puts "\n// Referenced type converters"
    typeConverterClasses.each do | classDecl | 
      # Add imports for type resolvers
      objectImplFile.puts "#import \"#{classDecl}.h\"\n"
      
      # Generate type resolver class files
      puts "Generating header for type converter class #{classDecl}"
      typeConverterHeaderFileNameTemp = "%s/%s.h" % [$tempDirectory, classDecl]
      typeConverterHeaderFile = File.new(typeConverterHeaderFileNameTemp, "w")

      # Generate type resolver header
      typeConverterHeaderFile.puts(fileHeaderForFilename("#{classDecl}.h"))
      typeConverterHeaderFile.puts "#import <Foundation/Foundation.h>\n\n"
      typeConverterHeaderFile.puts "@interface #{classDecl} : NSValueTransformer {\n"
      typeConverterHeaderFile.puts "}\n\n"
      typeConverterHeaderFile.puts "@end\n"
      
      typeConverterHeaderFile.close
      
      puts "Generating implementation for type resolver class #{classDecl}"
      typeConverterImplFileNameTemp = "%s/%s.m" % [$tempDirectory, classDecl]
      typeConverterImplFile = File.new(typeConverterImplFileNameTemp, "w")
      
      # Generate type resolver impl header
      typeConverterImplFile.puts(fileHeaderForFilename("#{classDecl}.m"))
      typeConverterImplFile.puts "#import \"#{classDecl}.h\"\n\n"
      typeConverterImplFile.puts "@implementation #{classDecl}\n\n"
      typeConverterImplFile.puts "+ (Class) transformedValueClass\n{\n"
      typeConverterImplFile.puts "\treturn [NSString class]; //TODO: Change this to the transformed class"
      typeConverterImplFile.puts "}\n\n"
      typeConverterImplFile.puts "+ (id) transformedValue:(id)valueAsString\n{\n"
      typeConverterImplFile.puts "\t//TODO: implement this method\n"
      typeConverterImplFile.puts "\treturn nil;\n"
      typeConverterImplFile.puts "}\n\n"
      typeConverterImplFile.puts "+ (BOOL)allowsReverseTransformation\n{\n"
      typeConverterImplFile.puts "\treturn NO; //TODO: Change this to YES if you decide to implement reverseTransformedValue:\n"
      typeConverterImplFile.puts "}\n\n"
      typeConverterImplFile.puts "+ (id) reverseTransformedValue:(id)value\n{\n"
      typeConverterImplFile.puts "\t//TODO: If you decide to implement this method, make sure to rseturn YES in allowsReverseTransformation\n"
      typeConverterImplFile.puts "\treturn nil;\n"
      typeConverterImplFile.puts "}\n\n"
      typeConverterImplFile.puts "@end\n"
      
      typeConverterImplFile.close
      
      applyDiffOrOverwriteFile("#{classDecl}.h", typeConverterHeaderFileNameTemp)
      applyDiffOrOverwriteFile("#{classDecl}.m", typeConverterImplFileNameTemp)
    end
  end
 
  # Assemble final header file contents
  objectImplFile.puts "\n@implementation #{mappedType}\n\n"
  
  objectImplFile.puts automaticPropertyImplLines
  
  if $coredata
    objectImplFile.puts "\n"
  else
    objectImplFile.puts "\n- (void) dealloc\n{\n"
    objectImplFile.puts deallocLines
    objectImplFile.puts "\t[super dealloc];\n}\n\n"
  end
  
  objectImplFile.puts "#pragma mark -\n#pragma mark Parsing / exporting\n\n"
  
  if $coredata
    objectImplFile.puts "+ (NSEntityDescription *) entityForClassInManagedObjectContext:(NSManagedObjectContext *)moc\n{\n"
    objectImplFile.puts "\t return [[[[moc persistentStoreCoordinator] managedObjectModel] entitiesByName] objectForKey:@\"#{objectId}\"];"
    objectImplFile.puts "}\n\n"
    
    objectImplFile.puts "- (id) initWithDictionary:(NSDictionary *)dict inManagedObjectContext:(NSManagedObjectContext *)moc\n{\n"

    # Support sub classes of business objects
    if extends
      objectImplFile.puts "\tif ((self = [super initWithDictionary:dict inManagedObjectContext:moc])) {\n"
    else
      objectImplFile.puts "\tif ((self = [super initWithEntity:[[self class] entityForClassInManagedObjectContext:moc] insertIntoManagedObjectContext:moc])) {\n"
    end
  else
    objectImplFile.puts "- (id) initWithDictionary:(NSDictionary *)dict\n{\n"

    # Support sub classes of business objects
    if extends
      objectImplFile.puts "\tif ((self = [super initWithDictionary:dict])) {\n"
    else
      objectImplFile.puts "\tif ((self = [super init])) {\n"
    end
  end
  
  # Common implementation between NSObject / NSManagedObject subclasses 
  if parserUsesTemporaryRawVariable
    objectImplFile.puts "\t\tid tempRawPropertyVar;"  
  end
  
  if parserUsesTemporaryInitVariable
    objectImplFile.puts "\t\tid tempInitPropertyVar;"  
  end
  
  objectImplFile.puts parserLines
  objectImplFile.puts "\t}\n\treturn self;\n}\n\n"

  objectImplFile.puts "- (NSDictionary *) dictionaryRepresentation\n{\n"  
  if extends
    objectImplFile.puts "\tNSMutableDictionary *bufferDict = [[super dictionaryRepresentation] mutableCopy];\n\n"
  else
    objectImplFile.puts "\tNSMutableDictionary *bufferDict = [[NSMutableDictionary alloc] init];\n\n"
  end
  objectImplFile.puts dictExporterLines
  objectImplFile.puts "\n\tNSDictionary *outputDict = [NSDictionary dictionaryWithDictionary:bufferDict];\n"
  objectImplFile.puts "\t[bufferDict release];\n"
  objectImplFile.puts "\treturn outputDict;\n}\n\n"

  objectImplFile.puts "- (NSString *) JSONRepresentation\n{\n"
  objectImplFile.puts "\treturn [[self dictionaryRepresentation] JSONRepresentation];\n}\n"
  
  # Generate NSCoding only for NSObject subclasses. It is not useful for NSManagedObjects.
  if not $coredata
    # NSCoding
    objectImplFile.puts "\n#pragma mark -\n#pragma mark NSCoding\n\n"

    # Support NSCoding for sub classes of business objects
    objectImplFile.puts "- (id) initWithCoder:(NSCoder *)decoder\n{\n"
    if extends
      objectImplFile.puts "\tif ((self = [super initWithCoder:decoder])) {\n"
    else
      objectImplFile.puts "\tif ((self = [super init])) {\n"
    end
    objectImplFile.puts decoderLines;
    objectImplFile.puts "\t}\n\treturn self;\n}\n\n"

    objectImplFile.puts "- (void) encodeWithCoder:(NSCoder *)encoder\n{\n"
    if extends
      objectImplFile.puts "\t[super encodeWithCoder:encoder];\n"
    end
    objectImplFile.puts encoderLines;
    objectImplFile.puts "}\n"

    # NSCopying
    objectImplFile.puts "\n#pragma mark -\n#pragma mark NSCopying\n\n"

    # Support NSCopying for sub classes of business objects
    objectImplFile.puts "- (id) copyWithZone:(NSZone *)zone\n{\n"
    if extends
      objectImplFile.puts "\t#{mappedType} *copy = [super copyWithZone:zone];\n\n"
    else
      objectImplFile.puts "\t#{mappedType} *copy = [[[self class] allocWithZone:zone] init];\n\n"
    end
    objectImplFile.puts copyLines;
    objectImplFile.puts "\n\treturn copy;\n"
    objectImplFile.puts "}\n"
  end
  
  objectImplFile.puts "\n@end\n"
  
  objectImplFile.close
  
  applyDiffOrOverwriteFile("#{mappedType}.h", objectHeaderFileNameTemp)
  applyDiffOrOverwriteFile("#{mappedType}.m", objectImplFileNameTemp)
end

##
## Main section
##
opts = GetoptLong.new(
  ['--help', '-h', GetoptLong::NO_ARGUMENT],
  ['--schema', '-s', GetoptLong::REQUIRED_ARGUMENT],
  ['--output-directory', '-o', GetoptLong::REQUIRED_ARGUMENT],
  ['--overwrite', GetoptLong::OPTIONAL_ARGUMENT ],
  ['--coredata', GetoptLong::OPTIONAL_ARGUMENT]
)

$inputFileName = nil
$outputDirectory = nil
$originalOutputDirectory = nil
$overwrite = false
$coredata = false

opts.each do |opt, arg|
  case opt
    when '--help'
      RDoc::usage
    when '--schema'
      $inputFileName = arg.to_s
    when '--output-directory'
      $outputDirectory = arg.to_s
      $originalOutputDirectory = "%s/original-output" % [$outputDirectory]
    when '--overwrite'
      $overwrite = true
    when '--coredata'
      $coredata = true
  end
end

if ($outputDirectory.nil? or ($inputFileName.nil? and STDIN.fcntl(Fcntl::F_GETFL, 0) != 0))
  RDoc::usage
end

# Make sure that the output directory and temp exist
FileUtils.mkdir_p $outputDirectory
FileUtils.mkdir_p $originalOutputDirectory
$tempDirectory = Dir.mktmpdir
$tempFile = `mktemp -t jsonschema2objc`
puts "Using temporary file #$tempFile"

# Load JSON schema definition and parse JSON
if STDIN.fcntl(Fcntl::F_GETFL, 0) == 0
  $schema = JSON.parse(STDIN.read)
else
  File.open($inputFileName) do | schemaFile |
    schemaFileContents = schemaFile.read
    $schema = JSON.parse(schemaFileContents)
  end
end

$schemaIndex = Hash.new

# Build object definitions index
$schema.each do | objectDefinition, index |
  objectType = objectDefinition["type"]
  case objectType
  when "object", "enum"
    objectId = objectDefinition["id"]
    if !objectId.empty?
      $schemaIndex[objectId] = objectDefinition
    else
      STDERR.puts "!!! Object definition at index #{index} is missing a unique id"
      exit 1
    end
  else
    STDERR.puts "!!! Object definition at index #{index} has unknown type #{objectType}"
    exit 1
  end
end

# Generate Objective C header / implementation files for each class
$schemaIndex.each do | objectId, objectDefinition |
  objectType = objectDefinition["type"]
  case objectType
  when "object"
    generateClassFiles(objectId, objectDefinition)
  when "enum"
    generateEnumFiles(objectId, objectDefinition)
  else
    STDERR.puts "!!! Unknown type #{objectType} for object ID #{objectId}"
    exit 1
  end
end