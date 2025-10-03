module lmd.endpoint;

import lmd.formatter;
import lmd.response;
import lmd.model;
import lmd.context;
import lmd.options;

interface IEndpoint
{
    ref string key();

    ref Model[string] models();

    ref IFormatter formatter();

    Model[] available();

    Model load(string name = null, 
        string owner = "organization_owner", 
        Options options = Options.init,
        Context context = Context.init);

    Response request(string api, Model model);

    Response completions(Model model);

    Response embeddings(Model model);
    
    ResponseStream stream(Model model, void delegate(Response) callback = null);
}