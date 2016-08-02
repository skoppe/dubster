/**
 * Dubster. Runs unittests on dub packages against latest dmd compiler's
 * Copyright (C) 2016  Sebastiaan Koppe
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
module dubster.dmd;

import std.regex;
import std.conv : to;
import vibe.d;
import std.algorithm : filter;
import std.range : isInputRange, ElementType, enumerate;
import dubster.docker;
import std.file : rename, exists;
import std.traits : hasMember;

struct GitCommit
{
	string sha;
	string url;
}
struct GitTag
{
	string name;
	string zipball_url;
	string tarball_url;
	GitCommit commit;
}
struct DmdVersion
{
	@name("_id") BsonObjectID id;
	Version ver;
	string sha;
	auto opCmp(const DmdVersion other)
	{
		return ver.opCmp(other.ver);
	}
}
struct Version
{
	int major;
	int minor;
	int patch;
	string postfix;
	int seq;
	auto opCmp(const Version other)
	{
		if (major < other.major)
			return -1;
		if (major > other.major)
			return 1;
		if (minor < other.minor)
			return -1;
		if (minor > other.minor)
			return 1;
		if (patch < other.patch)
			return -1;
		if (patch > other.patch)
			return 1;
		if (postfix.length == 0)
			return other.postfix.length == 0 ? 0 : 1;
		if (other.postfix.length == 0)
			return -1;
		if (postfix == other.postfix)
			return seq - other.seq;
		if (postfix == "rc")
			return 1;
		if (other.postfix == "rc")
			return -1;
		if (postfix == "b")
			return 1;
		if (other.postfix == "b")
			return -1;
		return 0;
	}
	string toString() const
	{
		import std.format : format;
		if (postfix.length != 0)
			return format("v%d.%03d.%d-%s%d",major,minor,patch,postfix,seq);
		return format("v%d.%03d.%d",major,minor,patch);
	}
}
Version parseVersion(string v)
{
	auto reg = ctRegex!`^v([0-9]+)\.([0-9]+)\.([0-9]+)(?:-(.+)([0-9]+))?$`;
	auto matches = v.matchFirst(reg);
	import std.stdio;
	switch (matches.length)
	{
		case 4:
			return Version(
				matches[1].to!int,
				matches[2].to!int,
				matches[3].to!int);
		case 6:
			return Version(
				matches[1].to!int,
				matches[2].to!int,
				matches[3].to!int,
				matches[4],
				matches[5].length == 0 ? int.init : matches[5].to!int);
		default:
			throw new Exception("Invalid version "~v);
	}
}
unittest
{
	assert(parseVersion("v2.071.1-b2") == Version(2,71,1,"b",2));
	assert(parseVersion("v2.071.1") == Version(2,71,1,"",int.init));
	assert(parseVersion("v2.071.1") < parseVersion("v2.071.2"));
	assert(parseVersion("v2.071.1") < parseVersion("v2.072.1"));
	assert(parseVersion("v2.071.1") < parseVersion("v3.071.1"));
	assert(parseVersion("v2.071.1-b2") < parseVersion("v2.071.1"));
	assert(parseVersion("v2.071.1-b2") < parseVersion("v2.071.1-b3"));
	assert(parseVersion("v2.071.1-b2") < parseVersion("v2.071.1-rc1"));
	assert(parseVersion("v2.071.1-rc1") < parseVersion("v2.071.1-rc2"));
	assert(parseVersion("v2.071.1-rc3") < parseVersion("v2.071.2"));
	assert(parseVersion("v2.071.1-b2") < parseVersion("v2.071.2"));
}
auto getDmdTags()
{
	GitTag[] tags;
	int statusCode;
	// we could also request ?page=2. look into the Link header
	requestHTTP("https://api.github.com/repos/dlang/dmd/tags",(scope req){
		req.method = HTTPMethod.GET;
	},(scope res){

		scope (exit) res.dropBody();
		statusCode = res.statusCode;
		if (statusCode != 200)
			throw new Exception("Invalid response");
		tags = res.readJson.deserializeJson!(GitTag[]);
	});
	return tags;
}
auto toReleases(Tags)(Tags tags)
	if (isInputRange!Tags && is(ElementType!(Tags) == GitTag))
{
	return tags.map!(c=>DmdVersion(BsonObjectID.generate,c.name.parseVersion,c.commit.sha));
}
auto importantOnly(Releases)(Releases versions)
	if (isInputRange!Releases && is(ElementType!(Releases) == DmdVersion))
{
	return versions.enumerate().filter!(i=>i.value.ver.postfix.length == 0 || i.index == 0).map!(i=>i.value);
}
bool alreadyInstalled(string sha)
{
	return exists("/Users/skoppe/dev/d/dubster/gen/"~sha);
}
string installCompiler(Meta, Sink)(DockerClient client, Meta meta, ref Sink sink)
	if (hasMember!(Meta,"sha"))
{
	if (alreadyInstalled(meta.sha))
		return "/Users/skoppe/dev/d/dubster/gen/"~meta.sha;

	sink.put("Dubster | Building DMD "~meta.sha~"\n");
	CreateContainerRequest req;
	req.image = "skoppe/dubster-digger";
	req.workingDir = "/digger-2.4-linux-64";
	req.entrypoint = ["./digger"];
	req.hostConfig.binds = ["/Users/skoppe/dev/d/dubster/gen/digger:/output"];
	static if (hasMember!(Meta,"ver"))
		req.cmd = ["build",meta.ver.toString()];
	else
		req.cmd = ["build",meta.sha];

	client.oneOffContainer(req,sink);
	rename("/Users/skoppe/dev/d/dubster/gen/digger/result","/Users/skoppe/dev/d/dubster/gen/"~meta.sha);

	sink.put("Dubster | Complete build DMD "~req.cmd[$-1]~"\n");
	return "/Users/skoppe/dev/d/dubster/gen/"~meta.sha;
}


