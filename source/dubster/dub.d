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
import vibe.data.bson : BsonObjectID;
import vibe.data.serialization : name;
import std.range : zip;
import std.array : array;
import std.algorithm : map, filter;
import arsd.dom;

import dubster.docker;

version (unittest) {
	import unit_threaded;
}
struct DubPackage
{
	BsonObjectID _id;
	string name;
	string ver;
	int opCmp(ref const DubPackage other)
	{
		import std.algorithm : cmp;
		auto r1 = cmp(name,other.name);
		if (r1 != 0)
			return r1;
		return cmp(ver,other.ver);
	}
}
auto getDiff(DubPackage[] pa, DubPackage[] pb)
{
	import std.algorithm : setDifference;
	return pa.setDifference(pb);
}
unittest
{
	import std.stdio;
	DubPackage[] empty;
	DubPackage abc100 = DubPackage("abc","1.0.0"), abc009 = DubPackage("abc","0.0.9");
	getDiff([abc100],[abc100]).shouldEqual(empty);
	getDiff([abc100],[abc009]).shouldEqual([abc100]);
	getDiff([abc100,abc009],[abc100,abc100]).shouldEqual([abc009]);
}
auto parseCodeDlangOrg()
{
	DubPackage[] packages;
	requestHTTP("http://code.dlang.org/",
		(scope req){

		},
		(scope res){
			auto doc = new Document(res.bodyReader.readAllUTF8());
			auto rows = doc.querySelectorAll("#content > table tr");//.map!(d=>d.innerHTML);
			auto names = rows.map!(p=>p.querySelector("tr td a")).filter!(p=>p !is null).map!(p=>p.innerHTML);
			auto versions = rows.map!(p=>p.querySelector("tr td:nth-child(2)")).filter!(p=>p !is null).map!(p=>p.firstInnerText()[1..$]);
			packages = names.zip(versions).map!(z=>DubPackage(BsonObjectID.generate,z[0],z[1])).array();
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

