module tests.json;

import intuit.json;
import unit_threaded;

import std.json : JSONType, JSONValue;
import std.typecons : Nullable;

enum Flavor : string
{
    Vanilla = "vanilla",
    Chocolate = "chocolate"
}

struct Metadata
{
    bool active;
}

struct Payload
{
    @Required @intuit.json.Name("display_name") string name;
    long[] values;
    Metadata[string] metadata;
    Nullable!double score;
    Flavor flavor;
}

@unit_threaded.Name("JSON serialization supports aggregates and containers")
unittest
{
    Payload payload;
    payload.name = "sample";
    payload.values = [1, 2, 3];
    payload.metadata["entry"] = Metadata(true);
    payload.score = Nullable!double(2.5);
    payload.flavor = Flavor.Chocolate;

    JSONValue json = payload.toJSON();

    json["display_name"].str.should == "sample";
    json["values"].array.length.should == 3;
    json["metadata"]["entry"]["active"].type.should == JSONType.true_;
    json["score"].floating.should == 2.5;
    json["flavor"].str.should == "chocolate";

    Payload recovered = fromJSON!Payload(json);
    recovered.name.should == payload.name;
    recovered.values.should == payload.values;
    recovered.metadata.should == payload.metadata;
    recovered.score.should == payload.score;
    recovered.flavor.should == payload.flavor;
}

@unit_threaded.Name("JSON deserialization enforces required fields") @ShouldFail
unittest
{
    fromJSON!Payload(JSONValue.emptyObject);
}

@unit_threaded.Name("JSON serialization handles null values")
unittest
{
    (cast(string)null).toJSON().type.should == JSONType.null_;
    (cast(int[])null).toJSON().type.should == JSONType.array;
    Nullable!int.init.toJSON().type.should == JSONType.null_;
    fromJSON!(int[])(JSONValue.init).shouldBeNull;
}
