/++
    syncs stuff over FTP.
 +/
module zor.syncstuff;

private:

import requests;
import std.algorithm.searching : canFind;
import std.conv : text, to;
import std.file : DirEntry, SpanMode, dirEntries, readText;
import std.json : JSONValue, parseJSON;
import std.path : baseName, dirName;
import std.stdio;


// FTP
/++
    FIXME
 +/
struct FTP
{
    string address;
    ushort port = 21;
    string login;
    string password;
    string baseDir;

    /++
        FIXME
     +/
    static FTP fromCredentialsFile(const string filename)
    {
        FTP ftp;
        const json = readText(filename).parseJSON();

        ftp.address = json["address"].str;
        ftp.port = json["port"].str.to!ushort;
        ftp.login = json["login"].str;
        ftp.password = json["password"].str;
        ftp.baseDir = json["baseDir"].str;

        return ftp;
    }

    /++
        FIXME
     +/
    JSONValue toJSON() const
    {
        JSONValue json;
        json = null;
        json.object = null;

        json["address"] = JSONValue(this.address);
        json["port"] = JSONValue(this.port.to!string);
        json["login"] = JSONValue(this.login);
        json["password"] = JSONValue(this.password);
        json["baseDir"] = JSONValue(this.baseDir);

        return json;
    }
}


// TrackedFile
/++
    FIXME
 +/
struct TrackedFile
{
    string filename;
    ulong size;
    long modified;

    /++
        FIXME
     +/
    this(DirEntry file)
    {
        this.filename = file.name;
        this.size = file.size;
        this.modified = file.timeLastModified.toUnixTime;
    }

    /++
        FIXME
     +/
    JSONValue toJSON() const
    {
        JSONValue json;
        json = null;
        json.object = null;

        //json["filename"] = JSONValue(this.filename);
        json["size"] = JSONValue(this.size.to!string);
        json["modified"] = JSONValue(this.modified.to!string);

        return json;
    }
}


// getCurrentFileIndex
/++
    FIXME
 +/
auto getCurrentFileIndex(const string path)
{
    struct Results
    {
        JSONValue json;
        size_t length;
    }

    Results res;
    auto files = dirEntries(path, SpanMode.depth, false);

    foreach (/*const*/ file; files)
    {
        if (!file.isFile || file.name.dirName.canFind("/.")) continue;
        res.json[file.name] = TrackedFile(file).toJSON();
        ++res.length;
    }

    return res;
}


// readStoredFileIndex
/++
    FIXME
 +/
JSONValue readStoredFileIndex(const string filename)
{
    return parseJSON(readText(filename));
}


// saveFileIndex
/++
    FIXME
 +/
void saveFileIndex(const JSONValue json, const string filename)
{
    auto file = File(filename, "w");
    file.writeln(json.toPrettyString);
}


// initResources
/++
    FIXME
 +/
bool initResources(const string indexFilename, const string credentialsFilename)
{
    import std.file : exists;

    bool initialisedCredentials;

    if (!indexFilename.exists)
    {
        JSONValue emptyJSON;
        emptyJSON = null;
        emptyJSON.object = null;

        File(indexFilename, "w").writeln(emptyJSON.toString);
    }

    if (!credentialsFilename.exists)
    {
        FTP ftp;
        ftp.address = "127.0.0.1";
        //ftp.port = 21;
        ftp.login = "[REDACTED]";
        ftp.password = "[REDACTED]";
        ftp.baseDir = ".";

        File(credentialsFilename, "w").writeln(ftp.toJSON.toPrettyString);
        initialisedCredentials = true;
    }

    return initialisedCredentials;
}


// uploadFile
/++
    FIXME
 +/
auto uploadFile(
    const string filename,
    const string remotePath,
    ref Request req,
    const uint chunkSize = 1024)
{
    auto file = File(filename, "rb");
    auto res = req.post(remotePath, file.byChunk(chunkSize));
    return res.code;
}


// run
/++
    FIXME
 +/
void run(
    const string path,
    const string indexFilename,
    const string credentialsFilename)
{
    import std.array : Appender;

    immutable ftp = FTP.fromCredentialsFile(credentialsFilename);
    auto index = getCurrentFileIndex(path);
    const storedJSON = readStoredFileIndex(indexFilename);

    Appender!(string[]) sink;
    sink.reserve(index.length);

    immutable indexRelative = "./" ~ indexFilename;
    immutable credentialsRelative = "./" ~ credentialsFilename;

    foreach (immutable filename, trackedFileJSON; index.json.object)
    {
        if ((filename == indexRelative) ||
            (filename == credentialsRelative) ||
            (filename == "./syncstuff")) continue;

        if (auto storedJSON = filename in storedJSON.object)
        {
            if (((*storedJSON)["size"].str != trackedFileJSON["size"].str) ||
                ((*storedJSON)["modified"].str != trackedFileJSON["modified"].str))
            {
                writeln("MODIFIED:", filename);
                sink ~= filename;
            }
        }
        else
        {
            writeln("NEW:", filename);
            sink ~= filename;
        }
    }

    if (sink[].length)
    {
        scope(exit) saveFileIndex(index.json, indexFilename);

        writeln(ftp.login, ':', ftp.password, '@', ftp.address, ':', ftp.port);
        writeln("to sync:");

        Request req;
        req.verbosity = 3;
        req.authenticator = new BasicAuthentication(ftp.login, ftp.password);
        immutable remoteBase = text("ftp://", ftp.address, ':', ftp.port, '/', ftp.baseDir);

        foreach (immutable filename; sink)
        {
            immutable remotePath = remoteBase ~ '/' ~ filename[2..$];
            writeln(filename, " --> ", remotePath);
            immutable code = uploadFile(filename, remotePath, req);
            writeln(code);
            const newJSON = TrackedFile(DirEntry(filename)).toJSON();
            index.json[filename] = newJSON;
        }
    }
    else
    {
        writeln("nothing to do.");
    }
}


public:


// main
/++
    FIXME
 +/
void main(string[] args)
{
    import std.getopt : defaultGetoptPrinter, config, getopt;

    string indexFilename = "index.json";
    string credentialsFilename = "credentials.json";
    bool wantsNewCredentials;
    bool init;

    auto results = getopt(args,
        config.caseSensitive,
        config.bundling,

        "index|i",
            "Path to index file ["~ indexFilename ~ "]",
            &indexFilename,

        "credentials|c",
            "Path to credentials file [" ~ credentialsFilename ~"]",
            &credentialsFilename,

        "newcred",
            "Generate new credentials file",
            &wantsNewCredentials,

        "init",
            "Reinitialises index file",
            &init,
    );

    immutable path = (args.length > 1) ? args[1] : ".";

    if (results.helpWanted)
    {
        defaultGetoptPrinter("syncstuffer\n", results.options);
        writeln("\nit syncs stuff.");
        return;
    }

    immutable initialisedCredentials = initResources(indexFilename, credentialsFilename);
    if (initialisedCredentials)
    {
        writeln("new credentials file created. [", credentialsFilename, ']');
        return;
    }

    if (init)
    {
        auto index = getCurrentFileIndex(path);
        saveFileIndex(index.json, indexFilename);
        writeln(index.json.toPrettyString);
        return;
    }

    return run(path, indexFilename, credentialsFilename);
}
