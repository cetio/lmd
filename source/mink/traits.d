module mink.traits;

static import std.traits;
import std.meta;

template Recurse(A...)
    if (A.length > 0)
{
    enum cache = false;

    static if (!cache)
    {
    static if (__traits(compiles, { enum _ = A[0]; }) && is(typeof(A[0]) == string))
    {
        static assert(0, "Using entirely string based recursives is not supported!");

        // alias S = AliasSeq!(A[0]);

        // static if (A.length > 1)
        // static foreach (B; A[1..$])
        // {
        //     static assert(is(typeof(B) == string));
        //     S = AliasSeq!(S, "."~B);
        // }

        // alias Recurse = mixin(S);
    }
    else
    {
        static assert(A.length == 1 || __traits(isModule, A[0]) || !__traits(isPackage, A[0]),
            "Using a root package as the root alias for recursion is not supported!");
        // TODO: This is bad and members should be able to be recursed when possible.
        static if (__traits(compiles, { enum _ = A[0]; }))
            enum Recurse = A[0];
        else
            alias Recurse = A[0];

        static if (A.length == 1 || __traits(isModule, A[0]) || !__traits(isPackage, A[0]))
        static if (A.length > 1)
        static foreach (B; A[1..$])
        {
            static if (__traits(compiles, { enum _ = B; }) && is(typeof(B) == string))
                Recurse = __traits(getMember, Recurse, B);
        }
    }
    }
}

template TypeRecurse(A...)
    if (A.length > 0)
{
    static if (isType!(Recurse!A))
        alias TypeRecurse = Recurse!A;
    else
        alias TypeRecurse = typeof(Recurse!A);
}

template DefaultInstantiate(A...)
    if (isTemplate!A)
{
    alias T = Recurse!A;

    string args()
    {
        import std.string : indexOf, split;

        string ret;
        static foreach (arg; T.stringof[(T.stringof.indexOf("(") + 1)..T.stringof.indexOf(")")].split(", "))
        {
            static if (arg.split(" ").length == 1 || arg.split(" ")[0] == "alias")
                ret ~= "void[], ";
            else
                ret ~= arg.split(" ")[0]~".init, ";
        }
        return ret[0..(ret.length >= 2 ? $-2 : $)];
    }

    alias DefaultInstantiate = mixin("T!("~args~")");
}

/* CORE */
// TODO: This is so horrifically ugly.
alias Parent(A...) = __traits(parent, Recurse!A);
alias Children(A...) = __traits(allMembers, Recurse!A);
alias GetChild(A...) = __traits(getMember, Recurse!(A[0..$-1]), A[$-1]);
alias AliasThis(A...) = __traits(getAliasThis, Recurse!A);
alias Attributes(A...) = __traits(getAttributes, Recurse!A);
enum Identifier(A...) =
{
    static if (isExpression!A)
        return A.stringof;
    static if (hasIdentifier!A)
        return __traits(identifier, A);
    else
        return A.stringof;
}();
alias GetUDAs(alias B, A...) = std.traits.getUDAs!(Recurse!A, B);
alias Unqual(A...) = std.traits.Unqual!(Recurse!A);
template TemplateArgs(A...)
{
    static if (__traits(compiles, std.traits.TemplateArgsOf!(Recurse!A)))
        alias TemplateArgs = std.traits.TemplateArgsOf!(Recurse!A);
}
template Parameters(A...)
{
    static if (isTemplated!A)
        alias Parameters = std.traits.Parameters!(Recurse!A);
    else static if (isLambda!(Recurse!A) && !__traits(compiles, { alias _ = std.traits.Parameters!(Recurse!A); }))
    {
        static assert(!isDynamicLambda!(Recurse!A), "Dynamic lambdas cannot be evaluated, please instantiate first!");
        import std.functional : toDelegate;

        typeof(toDelegate(Recurse!A)) dg;
        alias Parameters = std.traits.Parameters!dg;
    }
    else
        alias Parameters = std.traits.Parameters!(Recurse!A);
}
template ReturnType(A...)
{
    static if (isTemplated!A)
        alias ReturnType = std.traits.ReturnType!(Recurse!A);
    else static if (isLambda!(Recurse!A))
    {
        static assert(!isDynamicLambda!(Recurse!A), "Dynamic lambdas cannot be evaluated, please instantiate first!");
        import std.functional : toDelegate;

        typeof(toDelegate(Recurse!A)) dg;
        alias ReturnType = std.traits.ReturnType!dg;
    }
    else
        alias ReturnType = std.traits.ReturnType!(Recurse!A);
}
template Functions(A...)
{
    alias Functions = AliasSeq!();
    static foreach (C; Children!A)
    {
        static if (isFunction!(GetChild!(A, C)))
            Functions = AliasSeq!(Functions, C);
    }
}
template Fields(A...)
{
    alias Fields = AliasSeq!();
    static foreach (C; Children!A)
    {
        static if (isField!(GetChild!(A, C)))
            Fields = AliasSeq!(Fields, C);
    }
}
template Types(A...)
{
    alias Types = AliasSeq!();
    static foreach (C; Children!A)
    {
        static if (isType!(GetChild!(A, C)))
            Types = AliasSeq!(Types, C);
    }
}
template ElementType(T)
{
    static if (is(T == U[], U) || is(T == U*, U) || is(T U == U[L], size_t L))
        alias ElementType = U;
    else static if (isIndexable!T)
    {
        T _;
        alias ElementType = typeof(_[0]);
    }
    else
        alias ElementType = std.traits.OriginalType!T;
}
template Implements(T)
{
    private template Flatten(H, T...)
    {
        static if (T.length)
        {
            alias Flatten = AliasSeq!(Flatten!H, Flatten!T);
        }
        else
        {
            static if (!is(H == Object) && (is(H == class) || is(H == interface)))
                alias Flatten = AliasSeq!(H, Implements!H);
            else
                alias Flatten = Implements!H;
        }
    }

    static if (is(T S == super) && S.length)
    {
        static if (getAliasThis!T.length != 0)
            alias Implements = AliasSeq!(TypeOf!(T, getAliasThis!T), Implements!(TypeOf!(T, getAliasThis!T)), NoDuplicates!(Flatten!S));
        else
            alias Implements = NoDuplicates!(Flatten!S);
    }
    else
    {
        static if (getAliasThis!T.length != 0)
            alias Implements = AliasSeq!(TypeOf!(T, getAliasThis!T), Implements!(TypeOf!(T, getAliasThis!T)));
        else
            alias Implements = AliasSeq!();
    }
}

/* DESCRIPTORS */
enum hasIdentifier(A...) = __traits(compiles, { enum _ = __traits(identifier, Recurse!A); });
enum hasModifiers(A...) = isArray!A || isPointer!A || isEnum!A;
enum hasChildren(A...) = isModule!A || isPackage!A || (!isType!A || (!isBuiltinType!A && !hasModifiers!A));
enum hasParents(A...) = !isManifest!A && !(
    !__traits(compiles, { alias _ = Parent!A; }) ||
    !__traits(compiles, { enum _ = is(Parent!A == void); }) ||
    is(Parent!A == void));
enum hasUDA(alias B, A...) = std.traits.hasUDA!(Recurse!A, B);

enum isType(A...) = std.traits.isType!(Recurse!A);
enum isModule(A...) = __traits(isModule, Recurse!A);
enum isPackage(A...) = __traits(isPackage, Recurse!A);
enum isTemplated(A...) = __traits(compiles, std.traits.TemplateArgsOf!(Recurse!A));
enum isTemplate(A...) = !isType!A && !isExpression!A && (__traits(isTemplate, Recurse!A) || __traits(compiles, std.traits.TemplateOf!(Recurse!A)));
enum isFunction(A...) = std.traits.isFunction!(Recurse!A);
enum isFunctionPointer(A...) = std.traits.isFunctionPointer!(Recurse!A);
enum isDelegate(A...) = std.traits.isDelegate!(Recurse!A);
enum isLambda(A...) = hasIdentifier!A && Identifier!A.length > 8 && (Identifier!A)[0..8] == "__lambda";
enum isDynamicLambda(A...) = isLambda!A && is(typeof(Recurse!A) == void);
enum isCallable(A...) = isDelegate!A || isFunction!A || isFunctionPointer!A || isLambda!A;

// TODO: This shouldn't be here.
// TODO: How many things here can actually throw errors and I don't realize?
// TODO: If it returns an alias, it should be capital, if not, lowercase.
enum isTemplateOf(alias B, A...) =
{
    static if (__traits(compiles, { bool _ = __traits(isSame, std.traits.TemplateOf!B, Recurse!A); }))
        return __traits(isSame, Unqual!(std.traits.TemplateOf!B), Unqual!(Recurse!A));
    else
        return false;
}();
enum isImplementOf(alias B, A...) =
{
    bool ret;
    static foreach (C; Implements!B)
        ret |= is(C == B);
    return ret;
}();

enum isPointer(A...) = std.traits.isPointer!(TypeRecurse!A);
enum isArray(A...) = std.traits.isArray!(TypeRecurse!A);
enum isBuiltinType(A...) = std.traits.isBuiltinType!(TypeRecurse!A);
enum isClass(A...) = is(TypeRecurse!A == class);
enum isInterface(A...) = is(TypeRecurse!A == interface);
enum isStruct(A...) = is(TypeRecurse!A == struct);
enum isEnum(A...) = is(TypeRecurse!A == enum);
enum isUnion(A...) = is(TypeRecurse!A == union);
enum isAggregateType(A...) = std.traits.isAggregateType!(TypeRecurse!A);

enum isManifest(A...) = __traits(compiles, { enum _ = GetChild!(Parent!A, Identifier!A); });
enum isMutable(A...) = !isManifest!A && std.traits.isMutable!(Recurse!A);
enum isStatic(A...) = !isManifest!A && __traits(compiles, { static auto _() { return Recurse!A; } });
enum isField(A...) = !isManifest!A && !isCallable!A && !isType!A && !isPackage!A && !isModule!A && !isFunction!A && hasParents!A;
enum isExpression(A...) = !hasParents!A && __traits(compiles, { enum _ = Recurse!A; });
enum isLocal(A...) = !isManifest!A && !isField!A && __traits(compiles, { auto _ = Recurse!A; });

enum isSafe(A...) = std.traits.isSafe!(Recurse!A);
enum isUnsafe(A...) = std.traits.isUnsafe!(Recurse!A);
enum isAbstract(A...) = std.traits.isAbstractClass!(Recurse!A) || std.traits.isAbstractFunction!(Recurse!A);
enum isFinal(A...) = std.traits.isFinal!(Recurse!A);

/* RANGES */
enum isDynamicArray(A...) = std.traits.isDynamicArray!(TypeRecurse!A);
enum isStaticArray(A...) = __traits(isStaticArray, TypeRecurse!A);
enum isAssociativeArray(A...) = __traits(isAssociativeArray, TypeRecurse!A);
enum isIndexable(A...) =
{
    alias T = TypeRecurse!A;
    return __traits(compiles, { template t(T) { T v; auto t() => v[0]; } auto x = t!T; });
}();
enum isForward(A...) =
{
    alias T = TypeRecurse!A;
    return __traits(compiles, { template t(T) { T v; auto t() { foreach (u; v) { } } } alias x = t!T; });
}();
enum isBackward(A...) =
{
    alias T = TypeRecurse!A;
    return __traits(compiles, { template t(T) { T v; auto t() { foreach_reverse (u; v) { } } } alias x = t!T; });
}();
enum isSliceable(A...) =
{
    alias T = TypeRecurse!A;
    return __traits(compiles, { template t(T) { T v; auto t() => v[0..1]; } alias x = t!T; });
}();
enum isSliceAssignable(A...) =
{
    alias T = TypeRecurse!A;
    return __traits(compiles, { template t(T) { T v; auto t() => v[0..1] = v[1..2]; } alias x = t!T; }) && isMutable!(ElementType!T);
}();
enum isElement(alias A, alias B) = isAssignable!(B, ElementType!A);

/* NUMERICS */
enum isIntegral(A...) = __traits(isIntegral, TypeRecurse!A);
enum isScalar(A...) = __traits(isScalar, TypeRecurse!A);
enum isFloating(A...) = __traits(isFloating, TypeRecurse!A);
enum isUnsigned(A...) = __traits(isUnsigned, TypeRecurse!A);
enum isSigned(A...) = !isUnsigned!A;
enum isNumeric(A...) = isIntegral!A || isFloating!A;
enum isArithmetic(A...) =
{
    alias T = TypeRecurse!A;
    return __traits(compiles, { template t(T) { T v; auto t() => v + 1; } auto x = t!T; }) && isScalar!(ElementType!T);
}();
enum isVector(A...) = isArithmetic!A && isIndexable!A;

/* SEMANTICS */
// Technically delegates and associative arrays are also reference types, but they point to multiple sections of data.
enum isReferenceType(A...) = isClass!A || isInterface!A || isPointer!A || isDynamicArray!A;
enum isValueType(A...) = !isReferenceType!A && !isAssociativeArray!A && !isDelegate!A;
enum hasIndirections(A...) = std.traits.hasIndirections!(TypeRecurse!A);
enum isPOD(A...) = __traits(isPOD, TypeRecurse!A);
enum isCopyable(A...) = std.traits.isCopyable!(TypeRecurse!A);
enum isEqualityComparable(A...) = std.traits.isTestable!T || std.traits.isEqualityComparable!(TypeRecurse!A);
enum isOrderingComparable(A...) = std.traits.isOrderingComparable!(TypeRecurse!A);

// TODO: Maybe get rid of these? Here they must always be types.
enum isAssignable(A, B) = std.traits.isAssignable!(A, B);
enum isCovariantWith(A, B) = std.traits.isCovariantWith!(A, B);
enum isImplicitlyConvertible(A, B) = std.traits.isImplicitlyConvertible!(A, B);
enum isQualifierConvertible(A, B) = std.traits.isQualifierConvertible!(A, B);

enum hasAliasing(A...) = std.traits.hasAliasing!(Recurse!A);
enum hasUnsharedAliasing(A...) = std.traits.hasUnsharedAliasing!(Recurse!A);
enum hasElaborateAssign(A...) = std.traits.hasElaborateAssign!(Recurse!A);
enum hasElaborateCopyConstructor(A...) = std.traits.hasElaborateCopyConstructor!(Recurse!A);
enum hasElaborateDestructor(A...) = std.traits.hasElaborateDestructor!(Recurse!A);
enum hasElaborateMove(A...) = std.traits.hasElaborateMove!(Recurse!A);
enum hasExminkalFrameLimit(A...) =
{
    alias B = Recurse!A;

    static foreach (C; TemplateArgs!B)
    {
        static if (isFrameLimited!C)
            return true;
    }
    return false;
}();
enum isFrameLimited(A...) = isDelegate!A || isLocal!A || (isTemplated!A && hasExminkalFrameLimit!A);
