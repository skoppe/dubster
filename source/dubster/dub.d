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
module dubster.dub;

import vibe.core.core : runTask;
import vibe.http.client : requestHTTP;
import vibe.stream.operations : readAllUTF8;
import vibe.data.serialization : Name = name;
import vibe.data.json : deserializeJson;
import std.range : zip;
import std.array : array;
import std.algorithm : map, filter;
import dubster.docker;

struct DubPackage
{
	string _id;
	string name;
	string ver;
	string description;
	this(string n, string v, string d = "")
	{
		name = n;
		ver = v;
		description = d;
		_id = name~":"~ver;
	}
	int opCmp(inout const DubPackage other)
	{
		import std.algorithm : cmp;
		auto r1 = cmp(name,other.name);
		if (r1 != 0)
			return r1;
		return cmp(ver,other.ver);
	}
}
unittest
{
	assert(DubPackage("abc","1.0.0") == DubPackage("abc","1.0.0"));
	assert(DubPackage("abc","1.0.0") < DubPackage("abc","2.0.0"));
	assert(DubPackage("abc","2.0.0") > DubPackage("abc","1.0.0"));
	assert(DubPackage("abc","2.0.0") < DubPackage("def","1.0.0"));
}
auto getDiff(DubPackage[] pa, DubPackage[] pb)
{
	import std.algorithm : setDifference;
	return pa.setDifference(pb);
}
unittest
{
	import std.algorithm : equal;
	DubPackage[] empty;
	DubPackage abc100 = DubPackage("abc","1.0.0"), abc009 = DubPackage("abc","0.0.9");
	assert(getDiff([abc100],[abc100]).equal(empty));
	assert(getDiff([abc100],[abc009]).equal([abc100]));
	assert(getDiff([abc100,abc009],[abc100,abc100]).equal([abc009]));
}
auto parseCodeDlangOrg()
{
	struct Package
	{
		@Name("version") string ver;
		string name;
		string description;
	}
	DubPackage[] packages;
	requestHTTP("https://code.dlang.org/api/packages/search",
		(scope req){
		},
		(scope res){
			packages = res.readJson.deserializeJson!(Package[]).map!(p=>DubPackage(p.name,p.ver,p.description)).array;
		}
	);
	return packages;
}
auto buildPackage(Sink)(DockerClient client, DubPackage pkg, ref Sink sink, string compilerPath, long memoryLimit)
{
	sink.put("Dubster | Building package "~pkg.name~" "~pkg.ver~"\n");
	CreateContainerRequest req;
	req.image = "skoppe/dubster-dub";
	req.workingDir = "/";
	req.entrypoint = ["./run.sh"];
	req.hostConfig.memory = memoryLimit;
	// TODO: We can also introspect current container and find whatever volume is linked at /gen and use that
	req.hostConfig.volumesFrom = ["dubsterdata"];
	req.cmd = [pkg.name,pkg.ver,compilerPath~"/bin/dmd"];
	return client.oneOffContainer(req,sink);
}