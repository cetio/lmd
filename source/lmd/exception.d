module lmd.exception;

/// Represents an exception thrown by a model response or load.
class ModelException : Exception
{
    string code;
    string message;
    string param;
    string type;

    this(string code, string msg, string param, string type, string file = __FILE__, size_t line = __LINE__)
    {
        this.code = code;
        this.param = param;
        this.type = type;
        super(msg, file, line);
    }
}