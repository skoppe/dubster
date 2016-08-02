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
class DubsterApi : IDubsterApi
{
	private JobScheduler scheduler;
	this(JobScheduler scheduler)
	{
		this.scheduler = scheduler;
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
}
template hasBsonId(T)
{
	enum hasBsonId = true; // TODO: check if T has a member that is a BsonObjectID and is named _id or has an @name("_id") attribute
}
class Persistence
{
	private MongoCollection pendingJobs, dmds, packages, results;
	this(MongoClient client)
	{
		pendingJobs = client.getCollection("dubster.pendingJobs");
		dmds = client.getCollection("dubster.dmds");
		packages = client.getCollection("dubster.packages");
		results = client.getCollection("dubster.results");
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
class Server
{
	DmdVersion[] knownDmds;
	DubPackage[] knownPackages;
	JobScheduler scheduler;
	DubsterApi api;
	Persistence db;
	this(HTTPServerSettings settings, Persistence db, IReporter reporter)
	{
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
		api = new DubsterApi(scheduler);
		this.db = db;

		auto router = new URLRouter;
		router.registerRestInterface(api);
		listenHTTP(settings, router);

		restore();
		sync();
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
		import std.algorithm : setDifference, setIntersection, sort;
		import std.range : chain;
		import std.array : array;
		auto latestDmds = getDmdTags.toReleases.importantOnly.array.sort!"a > b"().array()[0..1];
		auto latestPackages = parseCodeDlangOrg.sort();

		auto newDmds = latestDmds.setDifference!"a > b"(knownDmds).array();
		if (newDmds.length > 0)
			writeln("Found a new dmd");
		auto newPackages = latestPackages.setDifference(knownPackages).array();
		if (newPackages.length > 0)
			writefln("Found %s new packages",newPackages.length);
		auto sameDmds = latestDmds.setIntersection!"a > b"(knownDmds);
		auto samePackages = latestPackages.setIntersection(knownPackages);

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
		setTimer(5.minutes, &this.sync, false);
	}
}



