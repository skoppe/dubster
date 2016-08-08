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
module dubster.server;

import vibe.d;
import dubster.job;
import dubster.dmd;
import dubster.dub;
import dubster.reporter;
import dubster.analyser;

import std.stdio;

struct JobResult
{
	Job job;
	Timestamp start;
	Timestamp finish;
	string output;
	ErrorStats error;
}
interface IDubsterApi
{
	// TODO: need to set no-cache
	Json getJob();
	@path("/job")
	void postJobResult(JobResult results);
	@path("/build/:dmd/:package")
	void postBuild(string _dmd, string _package);
	@path("/dmd")
	DmdVersion[] getDmds();
}
struct ServerSettings
{
	HTTPServerSettings httpSettings;
	bool doSync;
}
class JobScheduler
{
	private Job[] jobs;
	private IReporter reporter;
	this(IReporter r)
	{
		reporter = r;
	}
	Nullable!Job getJob()
	{
		auto n = Nullable!(Job)();
		if (jobs.length > 0)
		{
			n = jobs[0];
			jobs = jobs[1..$];
			reporter.executing(n.get);
		}
		return n;
	}
	void completeJob(JobResult results)
	{
		reporter.complete(results);
	}
	private void addJobs(Job[] jobs)
	{
		this.jobs ~= jobs;
	}
}
template hasBsonId(T)
{
	enum hasBsonId = true; // TODO: check if T has a member that is a BsonObjectID and is named _id or has an @name("_id") attribute
}
class Persistence
{
	private MongoCollection pendingJobs, dmds, packages, results;
	this(MongoDatabase db)
	{
		pendingJobs = db["pendingJobs"];
		dmds = db["dmds"];
		packages = db["packages"];
		results = db["results"];
	}
	private auto getCollection(alias name)()
	{
		static assert(
			hasMember!(Persistence,name) &&
			is(typeof(__traits(getMember, this, name)) : MongoCollection),
			"collection "~name~" doesn't exist");
		return __traits(getMember, this, name);
	}
	void append(alias name, T)(T[] t)
	{
		static assert(hasBsonId!T);
		getCollection!(name).insert(t);
	}
	void replace(alias name, T)(T[] t)
	{
		static assert(hasBsonId!T);
		auto collection = getCollection!name;
		try collection.drop(); catch(Exception e) {}
		collection.insert(t);
	}
	auto readAll(alias name, T)()
	{
		static assert(hasBsonId!T);
		return getCollection!(name).find!T();
	}
	void remove(alias name, T)(T t)
	{
		static assert(hasBsonId!T);
		getCollection!(name).remove(t);
	}
}
auto createJobs(DmdVersions,DubPackages)(DmdVersions dmds, DubPackages packages)
{
	import std.algorithm : cartesianProduct;
	return dmds.cartesianProduct(packages).map!((t)=>Job(BsonObjectID.generate(),t[0],t[1]));
}
class Server : IDubsterApi
{
	DmdVersion[] knownDmds;
	DubPackage[] knownPackages;
	JobScheduler scheduler;
	Persistence db;
	ServerSettings settings;
	this(ServerSettings s, Persistence db, IReporter reporter)
	{
		settings = s;
		scheduler = new JobScheduler(new class IReporter {
			override void executing(Job job)
			{
				reporter.executing(job);
			}
			override void complete(JobResult results)
			{
				db.append!("results")([results]);
				db.remove!("pendingJobs")(results.job);
				reporter.complete(results);
			}
		});
		this.db = db;

		auto router = new URLRouter;
		router.registerRestInterface(this);
		listenHTTP(s.httpSettings, router);

		restore();
		if (s.doSync)
			sync();
	}
	Json getJob()
	{
		auto job = scheduler.getJob();
		if (!job.isNull())
			return job.get().serializeToJson();
		return Json(null);
	}
	void postJobResult(JobResult results)
	{
		scheduler.completeJob(results);
	}
	void postBuild(string _dmd, string _package)
	{
		if (_dmd == "*")
		{
			if (_package == "*")
				throw new RestException(400,
					Json([
						"code":Json(1000),
						"msg":Json("Be more specific with your build requests, at minimum select a dmd version or a package version.")
					]));
			// schedule jobs for specific package with all known dmds
			throw new RestException(500,Json(["code":Json(2000),"msg":Json("Not implemented")]));
		}
		Version dmdVersion = parseVersion(_dmd);
		auto dmd = knownDmds.find!((a)=>a.ver == dmdVersion);
		if (dmd.empty)
			throw new RestException(400,Json(["code":Json(1001),"msg":Json("Unknown dmd version")]));
		if (_package == "*")
		{
			// schedule jobs for specific dmd with all known packages
			throw new RestException(500,Json(["code":Json(2000),"msg":Json("Not implemented")]));
		}
		auto p = _package.split(":");
		if (p.length != 2)
			throw new RestException(400,Json(["code":Json(1002),"msg":Json("Invalid package, needs : and a version")]));

		auto pkg = DubPackage(BsonObjectID.generate(),p[0],[1]);

		scheduler.addJobs([Job(BsonObjectID.generate(),dmd.front,pkg)]);
	}
	DmdVersion[] getDmds()
	{
		return knownDmds;
	}
	private void restore()
	{
		auto previous = db.readAll!("pendingJobs",Job).array();
		if (previous.length > 0)
			writefln("Found %s previous jobs: ",previous.length);
		scheduler.addJobs(previous);
		knownDmds = db.readAll!("dmds",DmdVersion).array();
		knownPackages = db.readAll!("packages",DubPackage).array();
	}
	private void sync()
	{
		import std.algorithm : setDifference, setIntersection, sort, uniq;
		import std.range : chain;
		import std.array : array;
		try
		{
			auto latestDmds = getDmdTags.toReleases.importantOnly.array.sort().array();
			auto latestPackages = parseCodeDlangOrg.sort();

			auto newDmds = latestDmds.setDifference(knownDmds).array();
			if (newDmds.length > 0)
				writefln("Found %s new dmds", newDmds.length);
			auto newPackages = latestPackages.setDifference(knownPackages).array();
			if (newPackages.length > 0)
				writefln("Found %s new packages",newPackages.length);
			auto sameDmds = latestDmds.setIntersection(knownDmds).array();
			auto samePackages = latestPackages.setIntersection(knownPackages).array();

			auto jobs = chain(
				createJobs(knownDmds, newPackages),
				createJobs(newDmds, knownPackages),
				createJobs(newDmds, newPackages)
			).array();

			if (jobs.length > 0)
				writefln("Created %s new jobs",jobs.length);

			knownDmds = chain(newDmds,sameDmds).array.sort().array();
			knownPackages = chain(newPackages,samePackages).array.sort().array();
			if (jobs.length > 0)
				db.append!"pendingJobs"(jobs);
			db.replace!"dmds"(knownDmds);
			db.replace!"packages"(knownPackages);

			scheduler.addJobs(jobs);
		} catch (Exception e)
		{
			writefln("Error in sync(): %s",e.msg);
		}
		setTimer(1.minutes, &this.sync, false);
	}
}



