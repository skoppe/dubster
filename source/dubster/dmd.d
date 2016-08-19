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
import std.conv : to, text;
import std.algorithm : filter, cmp;
import std.range : isInputRange, ElementType, enumerate;
import std.file : rename, exists;
import std.traits : hasMember;
import vibe.d;
import dubster.docker;
import std.digest.sha;

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
auto isValidDmdVersion(string ver)
{
	auto versionReg = ctRegex!`^v([0-9]+)\.([0-9]+)\.([0-9]+)(?:-(.+)([0-9]+))?$`;
	return ver.matchFirst(versionReg);
}
auto isValidDiggerVersion(string ver)
{
	auto basePullOrBranch = ctRegex!`^\w+ \+ ((\w+#[1-9][0-9]*)|(([A-Za-z-0-9]+\/){2}[A-Za-z-0-9]+))$`;
	return ver.matchFirst(basePullOrBranch) || ver.isValidDmdVersion;
}
auto isValidDiggerVersion(DmdVersion ver) { return ver.ver.isValidDiggerVersion(); }

struct DmdVersion
{
	@name("_id") string id;
	string ver;
	this(string v, string i = null)
	{
		ver = v;
		if (i is null)
		{
			if (v.isValidDmdVersion)
				id = v;
			else
				id = sha1Of(v).toHexString().text;
		} else
			id = i;
	}
	auto opCmp(const DmdVersion other)
	{
		return id.cmp(other.id);
	}
}
@("isValidDiggerVersion")
unittest
{
	assert(DmdVersion("v2.061.1-b2").isValidDiggerVersion);
	assert(DmdVersion("master + dmd#123").isValidDiggerVersion);
	assert(DmdVersion("master + phobos#123").isValidDiggerVersion);
	assert(DmdVersion("master + druntime#123").isValidDiggerVersion);
	assert(DmdVersion("master + Username/dmd/awesome-feature").isValidDiggerVersion);
	assert(!DmdVersion("master+ druntime#123").isValidDiggerVersion);
	assert(!DmdVersion("master+druntime#123").isValidDiggerVersion);
}
@("DmdVersion")
unittest
{
	assert(DmdVersion("v2.061.1-b2").id == "v2.061.1-b2");
	assert(DmdVersion("master + Username/dmd/awesome-feature").id == "DC09B6E93C54499D72AA197B02FB62B7C4D9561F");
	assert(DmdVersion("master + phobos#123").id == "327ADF40998E1B333184B885DCBAD1952166F7A6");
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
	return tags.map!(c=>DmdVersion(c.name));
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
@("Version")
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
/** drops patches, release-candidates and beta's whenever they are followed by a newer patch */
auto importantOnly(Releases)(Releases releases)
	if (isInputRange!Releases && is(ElementType!(Releases) == DmdVersion))
{
	// todo: can probably be done easier with sliding window and a filter
	import std.algorithm : sort, chunkBy, map, joiner, find, uniq;
	import std.range : tail, front, take, chain, drop, retro;
	import std.array : array;

	auto versions = releases.map!(v=>parseVersion(v.ver)).array().sort();
	auto grouped = versions.chunkBy!((a,b){
		return a.major == b.major && a.minor == b.minor;
	}).array();
	auto head = grouped.take(grouped.length-1);
	auto last = grouped.tail(1);

	auto preLast = last.map!((g){
		return chain(
			g.array().retro.find!(a=>a.postfix.length == 0).take(1),
			g.tail(1)
		).uniq;
	}).joiner;

	return chain(
		head.map!(g=>g.tail(1).front),
		preLast
	).map!(v=>DmdVersion(v.toString));
}
@("importantOnly")
unittest
{
	import std.algorithm : equal;
	assert([DmdVersion("v2.061.1-b2")].importantOnly.equal([DmdVersion("v2.061.1-b2")]));
	assert([DmdVersion("v2.060.1-b1"),DmdVersion("v2.060.1-b2")].importantOnly.equal([DmdVersion("v2.060.1-b2")]));
	assert([DmdVersion("v2.060.1-rc1"),DmdVersion("v2.060.1-rc2")].importantOnly.equal([DmdVersion("v2.060.1-rc2")]));
	assert([DmdVersion("v2.061.1"),DmdVersion("v2.061.2")].importantOnly.equal([DmdVersion("v2.061.2")]));
	assert([DmdVersion("v2.060.1"),DmdVersion("v2.060.2"),DmdVersion("v2.061.1-b1"),DmdVersion("v2.061.1-rc1"),DmdVersion("v2.061.1"),DmdVersion("v2.061.2")].importantOnly.equal([DmdVersion("v2.060.2"),DmdVersion("v2.061.2")]));
	assert([DmdVersion("v2.060.1"),DmdVersion("v2.060.2-rc1")].importantOnly.equal([DmdVersion("v2.060.1"),DmdVersion("v2.060.2-rc1")]));
	assert([DmdVersion("v2.060.1"),DmdVersion("v2.060.2-b1")].importantOnly.equal([DmdVersion("v2.060.1"),DmdVersion("v2.060.2-b1")]));
	assert([DmdVersion("v2.060.1"),DmdVersion("v2.060.2-b1"),DmdVersion("v2.060.2-rc1")].importantOnly.equal([DmdVersion("v2.060.1"),DmdVersion("v2.060.2-rc1")]));
}
bool alreadyInstalled(string sha)
{
	return exists("/gen/"~sha);
}
string installCompiler(Sink)(DockerClient client, DmdVersion dmd, ref Sink sink)
{
	if (alreadyInstalled(dmd.id))
		return "/gen/"~dmd.id;

	sink.put("Dubster | Building DMD "~dmd.ver~"\n");
	CreateContainerRequest req;
	req.image = "skoppe/dubster-digger";
	req.workingDir = "/digger-2.4-linux-64";
	req.entrypoint = ["./digger"];
	// TODO: We can also introspect current container and find whatever volume is linked at /gen and use that
	req.hostConfig.volumesFrom = ["dubsterdata"];
	req.cmd = ["build",dmd.ver];

	client.oneOffContainer(req,sink,Duration.max());
	rename("/gen/digger/result","/gen/"~dmd.id);

	sink.put("Dubster | Complete build DMD "~req.cmd[$-1]~"\n");
	return "/gen/"~dmd.id;
}


