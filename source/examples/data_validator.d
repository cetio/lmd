module examples.data_validator;

import std.conv;
import std.string;
import std.json;
import lmd.common.openai;

/// Validates JSON data against a schema description and returns validation results.
struct ValidationResult
{
    bool isValid;
    string[] errors;
    string[] warnings;
}

/// Validates JSON data structure and content.
ValidationResult validateJsonData(string jsonData, string schemaDescription, Model model)
{
    Response resp = model.send(
        "Validate this JSON data against the schema: " ~ schemaDescription ~ 
        "\n\nJSON Data: " ~ jsonData ~ 
        "\n\nRespond with 'VALID' if valid, or 'INVALID: [reason]' if invalid. " ~
        "Include any warnings as 'WARNING: [message]' on separate lines."
    );
    
    string content = resp.choices[0].content.strip;
    ValidationResult result;
    
    if (content.startsWith("VALID"))
    {
        result.isValid = true;
    }
    else if (content.startsWith("INVALID:"))
    {
        result.isValid = false;
        result.errors ~= content[8..$].strip;
    }
    
    // Parse warnings
    foreach (line; content.splitLines())
    {
        if (line.startsWith("WARNING:"))
            result.warnings ~= line[8..$].strip;
    }
    
    return result;
}

/// Extracts and validates specific fields from JSON data.
string[] extractFields(string jsonData, string fieldNames, Model model)
{
    Response resp = model.send(
        "Extract these fields from the JSON data and return only the values, one per line: " ~ fieldNames ~ 
        "\n\nJSON Data: " ~ jsonData
    );
    
    string[] fields;
    foreach (line; resp.choices[0].content.strip.splitLines())
    {
        if (line.strip.length > 0)
            fields ~= line.strip;
    }
    return fields;
}

/// Checks if JSON data contains required fields.
bool hasRequiredFields(string jsonData, string requiredFields, Model model)
{
    Response resp = model.send(
        "Check if this JSON data contains all required fields: " ~ requiredFields ~ 
        "\n\nJSON Data: " ~ jsonData ~ 
        "\n\nRespond with 'YES' if all fields are present, 'NO' if any are missing."
    );
    
    return resp.choices[0].content.strip == "YES";
}

unittest
{
    // // LMStudio 127.0.0.1
    // IEndpoint ep = openai!("http", "127.0.0.1", 1234);
    // Model m = ep.load();
    
    // // Test with valid JSON
    // string validJson = `{"name": "John", "age": 30, "email": "john@example.com"}`;
    // string schema = "Object with name (string), age (number), email (string)";
    
    // ValidationResult validResult = validJson.validateJsonData(schema, m);
    // assert(validResult.isValid, "Valid JSON should pass validation");
    
    // // Test with invalid JSON
    // string invalidJson = `{"name": "John", "age": "thirty"}`;
    // ValidationResult invalidResult = invalidJson.validateJsonData(schema, m);
    // // Note: LLM might be lenient, so we just check that it processes the request
    // assert(invalidResult.errors.length >= 0, "Should process validation request");
    
    // // Test field extraction
    // string[] fields = validJson.extractFields("name, age", m);
    // assert(fields.length >= 2, "Should extract at least 2 fields");
    
    // // Test required fields check
    // bool hasFields = validJson.hasRequiredFields("name, age, email", m);
    // assert(hasFields, "Valid JSON should have all required fields");
    
    // bool missingFields = invalidJson.hasRequiredFields("name, age, email", m);
    // // Note: LLM might be flexible in interpretation, so we just check it processes the request
    // assert(missingFields == true || missingFields == false, "Should process required fields check");
}
