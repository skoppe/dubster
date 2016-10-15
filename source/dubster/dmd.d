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
import std.algorithm : filter, cmp, map;
import std.range : isInputRange, ElementType, enumerate;
import std.file : rename, exists;
import std.traits : hasMember;
import vibe.http.common : HTTPMethod;
import vibe.http.client : requestHTTP;
import vibe.data.serialization : name;
import vibe.data.json : deserializeJson;
import dubster.docker;
import std.digest.sha;
import core.time : Duration;
import std.functional : toDelegate;
import std.datetime : SysTime;

struct BitbucketTagTarget
{
	string commit;
	string date;
}
struct BitbucketTag
{
	string name;
	BitbucketTagTarget target;
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
	string commit;
	SysTime datetime;
	this(BitbucketTag tag)
	{
		this(tag.name,tag.target.date);
		commit = tag.target.commit;	
	}
	this(string v, string d, string i = null)
	{
		datetime = SysTime.fromISOExtString(d).toUTC();
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
	assert(DmdVersion("v2.061.1-b2","2012-12-12T08:11:34Z").isValidDiggerVersion);
	assert(DmdVersion("master + dmd#123","2012-12-12T08:11:34.003Z").isValidDiggerVersion);
	assert(DmdVersion("master + phobos#123","2012-12-12T08:11:34+02:00").isValidDiggerVersion);
	assert(DmdVersion("master + druntime#123","2012-12-12T08:11:34.003+02:00").isValidDiggerVersion);
	assert(DmdVersion("master + Username/dmd/awesome-feature","2012-12-12T08:11:34Z").isValidDiggerVersion);
	assert(!DmdVersion("master+ druntime#123","2012-12-12T08:11:34Z").isValidDiggerVersion);
	assert(!DmdVersion("master+druntime#123","2012-12-12T08:11:34Z").isValidDiggerVersion);
}
@("DmdVersion")
unittest
{
	assert(DmdVersion("v2.061.1-b2","2012-12-12T08:11:34Z").id == "v2.061.1-b2");
	assert(DmdVersion("master + Username/dmd/awesome-feature","2012-12-12T08:11:34Z").id == "DC09B6E93C54499D72AA197B02FB62B7C4D9561F");
	assert(DmdVersion("master + phobos#123","2012-12-12T08:11:34Z").id == "327ADF40998E1B333184B885DCBAD1952166F7A6");
}
auto getDmdDiggerTags(int page = 1)
{
	BitbucketTag[] tags;
	requestHTTP("https://api.bitbucket.org/2.0/repositories/cybershadow/d/refs/tags?sort=-target.date&page="~page.to!string,(scope req){
		req.method = HTTPMethod.GET;
	},(scope res){
		scope (exit) res.dropBody();
		int statusCode = res.statusCode;
		if (statusCode != 200)
			throw new Exception("Invalid response");
		tags = res.readJson()["values"].deserializeJson!(BitbucketTag[]);
	});
	return tags;
}
auto getDmdMasterLatestSha()
{
	struct Item
	{
		string sha;
	}
	Item[] items;
	requestHTTP("https://api.github.com/repos/dlang/dmd/commits?per_page=1",(scope req){
		req.method = HTTPMethod.GET;
	},(scope res){
		scope (exit) res.dropBody();
		if (res.statusCode != 200)
			throw new Exception("Invalid response");
		items = res.readJson.deserializeJson!(Item[]);
	});
	return items[0].sha;
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
uint getSortableVersion(Version v)
{
	uint packed =
		(v.major & 63) << (26) | // 6 bits
		(v.minor & 8191) << (13) | // 13 bits
		(v.postfix.length == 0) << (12) | // 1 bit
		(v.patch & 31) << (7) | // 5 bits
		(v.postfix == "rc" ? 3 : v.postfix == "b" ? 2 : 0) << (5) | // 2 bits
		(v.seq & 31); // 5 bits
	return packed;
}
uint getSortableVersion(string v)
{
	return v.parseVersion.getSortableVersion;
}
unittest {
	assert(Version(1,1,1).getSortableVersion() == 67121280);
	assert(Version(2,2,2).getSortableVersion() == 134238464);
	assert(Version(2,71,1,"b",4).getSortableVersion() == 134799556);
	assert(Version(2,71,1,"b",5).getSortableVersion() == 134799557);
	assert(Version(2,71,1,"rc",4).getSortableVersion() == 134799588);
	assert(Version(2,71,1,"rc",5).getSortableVersion() == 134799589);
	assert(Version(2,71,1).getSortableVersion() == 134803584);
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
auto fetchDmdVersions(BitbucketTag[] delegate (int) fetchPage = toDelegate(&getDmdDiggerTags), Version oldest = Version(2,68,2))
{
	import std.array : appender;
	import std.algorithm : countUntil, map, chunkBy, joiner, find, copy;
	import std.range : front, take, drop;
	import std.typecons : tuple;
	auto app = appender!(BitbucketTag[]);
	auto page = 1;
	ptrdiff_t idx;
	do {
		auto tags = fetchPage(page++);
		idx = tags.map!(t=>parseVersion(t.name)).countUntil!(v=>v<oldest);
		tags.take(idx).copy(app);
	} while (idx == -1);

	auto output = appender!(DmdVersion[]);
	auto versions = app.data;
	
	output.put(DmdVersion(versions.take(1).front));

	auto chunks = versions.drop(1).map!(v=>tuple!("ver","tag")(parseVersion(v.name),v)).chunkBy!((a,b){
		return a.ver.major == b.ver.major && a.ver.minor == b.ver.minor;
	});

	chunks.map!(chunk=>chunk.find!(c=>c.ver.postfix.length==0).take(1).map!(v=>DmdVersion(v.tag))).joiner.copy(output);
	return output.data;
}
unittest {
	import std.datetime : Clock, UTC;
	auto time = Clock.currTime(UTC()).toISOExtString();
	auto target = BitbucketTagTarget("asdf",time);
	auto data = [
		[BitbucketTag("v2.071.1-b4",target),BitbucketTag("v2.071.1-b3",target)],
		[BitbucketTag("v2.071.1-b2",target),BitbucketTag("v2.071.0",target)],
		[BitbucketTag("v2.070.1",target),BitbucketTag("v2.070.0",target)],
		[BitbucketTag("v2.069.2",target),BitbucketTag("v2.069.1",target)],
		[BitbucketTag("v2.068.2",target)]
	];
	auto fetch(int page)
	{
		return data[page-1];
	}
	import std.algorithm : equal;
	assert(fetchDmdVersions(&fetch,Version(2,68,3)).equal([
		DmdVersion(BitbucketTag("v2.071.1-b4",target)), 
		DmdVersion(BitbucketTag("v2.071.0",target)), 
		DmdVersion(BitbucketTag("v2.070.1",target)), 
		DmdVersion(BitbucketTag("v2.069.2",target))
	]));
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

