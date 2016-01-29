
```
[
	{
		"id" : "Member",
		"type" : "object",
		"mappedType" : "BKMember",
		"properties" : {
			"FirstName" : {
				"type" : "string",
				"mappedProperty" : "firstName"
			},
			"LastName" : {
				"type" : "string",
				"mappedProperty" : "lastName"
			},
			"Id" : {
				"type" : "string",
				"mappedProperty" : "memberId"
			}
		}
	},
	{
		"id":"Address",
		"type":"object",
		"mappedType":"BKAddress",
		"properties":{
			"MemberId":{
				"type":"string",
				"mappedProperty":"memberId"
			},
			"LastName":{
				"type":"string",
				"mappedProperty":"lastName",
                "propertyCanBeNullObject" : false
			},
			"FirstName":{
				"type":"string",
				"mappedProperty":"firstName",
                "propertyCanBeNullObject" : false
			},
			"Address1":{
				"type":"string",
				"mappedProperty":"address1"
			},
			"Address2":{
				"type":"string",
				"mappedProperty":"address2",
				"propertyCanBeNullObject" : false
			},
			"Address3":{
				"type":"string",
				"mappedProperty":"address3",
				"propertyCanBeNullObject" : false
			},
			"ZipCode":{
				"type":"string",
				"mappedProperty":"zipCode"
			},
			"City":{
				"type":"string",
				"mappedProperty":"city"
			},
			"Digicode":{
				"type":"string",
				"mappedProperty":"digiCode",
				"propertyCanBeNullObject" : false
			},
			"Floor":{
				"type":"integer",
				"mappedProperty":"floor",
				"propertyCanBeNullObject" : false
			},
			"State":{
				"type":"string",
				"mappedProperty":"state",
				"propertyCanBeNullObject" : false
			},
			"CountryId":{
				"description":"Integer maps to enum of type CountryId",
				"type":"integer",
				"mappedType":"BKCountry",
				"mappedProperty":"countryId"
			},
			"CompanyName":{
				"type":"string",
				"mappedProperty":"companyName",
				"propertyCanBeNullObject" : false
			},
			"Telephone":{
				"type":"string",
				"mappedProperty":"telephone",
                "propertyCanBeNullObject" : false
			},
			"Email":{
				"type":"string",
				"mappedProperty":"email",
				"propertyCanBeNullObject" : false
			}
		}
	},
	{
		"id":"MemberAddress",
		"type":"object",
		"extends" : {
			"$ref" : "Address"
		},
		"mappedType":"BKMemberAddress",
		"properties":{
			"Sequence":{
				"type":"integer",
				"mappedProperty":"sequence"
			},
			"AddressName":{
				"type":"string",
				"mappedProperty":"addressName"
			},
			"PickupPointId":{
				"type":"string",
				"mappedProperty":"pickupPointId"
			}
		}
	},
	{
		"id":"Country",
		"type":"enum",
		"mappedType":"BKCountry",
		"values":[
			{"France":1},
			{"Germany":2},
			{"Spain":3},
			{"Italy":4},
			{"UnitedKingdom":5}
		]
	}
]
```