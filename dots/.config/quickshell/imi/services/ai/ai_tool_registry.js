// One declaration per tool - the fold (the fork's AiToolRegistry idea).
//
// A tool used to be spelled three times: once per dialect schema and once in
// the dispatcher, and the three had already started to disagree (gemini
// never learned generate_image). The registry rows live in
// AiToolRegistry.qml; these functions render them into each dialect's wire
// shape, and the skeleton contract holds the dispatcher to the same list.
.pragma library

function _forDialect(defs, dialect) {
    return (defs || []).filter(function (d) {
        return (d.dialects || []).indexOf(dialect) !== -1;
    });
}

// OpenAI (and mistral, same shape): {type:"function", function:{...}}.
function toOpenAiTools(defs, dialect) {
    return _forDialect(defs, dialect).map(function (d) {
        return { "type": "function", "function": {
            "name": d.name,
            "description": d.description,
            "parameters": d.parameters || {}
        } };
    });
}

// Gemini functionDeclarations: bare rows; a tool with no parameters OMITS
// the key (the wire shape the hand-written block always used).
function toGeminiDeclarations(defs) {
    return _forDialect(defs, "gemini").map(function (d) {
        var row = { "name": d.name, "description": d.description };
        if (d.parameters && Object.keys(d.parameters).length > 0)
            row["parameters"] = d.parameters;
        return row;
    });
}

function namesFor(defs, dialect) {
    return _forDialect(defs, dialect).map(function (d) { return d.name; });
}

function allNames(defs) {
    return (defs || []).map(function (d) { return d.name; });
}
