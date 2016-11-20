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
module dubster.job;

import std.algorithm : countUntil, remove, sort, map, cmp;
import std.range : retro, empty, front, popFront;
import std.datetime : Clock;
import std.typecons : Nullable;
import dubster.dub;
import dubster.dmd;
import dubster.reporter;
import dubster.analyser;
import vibe.data.serialization : name;
import vibe.http.common : HTTPMethod;
import vibe.http.client : requestHTTP;
import std.conv : to, text;
import std.digest.sha;
import std.array : appender, array;

struct Job
{
	@name("_id") string id;
	DmdVersion dmd;
	DubPackage pkg;
	string jobSet;
	JobTrigger trigger;
	string triggerId;
	Timestamp creation;
  Timestamp modified;
  Timestamp start;
  Timestamp finish;
  ErrorStats result;
  JobStatus status = JobStatus.Pending;
}
enum JobStatus
{
  All = 0,
  Pending = 1,
  Executing = 2,
  Completed = 3
}
struct RawJobResult
{
	@name("_id") string jobId;
	string dmdId;
	string pkgId;
	string output;
	Timestamp start;
	Timestamp finish;
	Timestamp creation;
}
auto extendWith(Job j, RawJobResult r)
{
  j.finish = r.finish;
  j.result = r.output.parseError();
  return j;
}
enum JobTrigger:string
{
	DmdRelease = "DmdRelease",
	PackageUpdate = "PackageUpdate",
	Manual = "Manual",
	DmdPullRequest = "DmdPullRequest",
	DruntimePullRequest = "DruntimePullRequest",
	PhobosPullRequest = "PhobosPullRequest",
	Nightly = "Nightly"
}
struct JobSet
{
	JobTrigger trigger;
	string triggerId;
	int priority = 0; // 0 is normal, -x is lower, +x is higher
	@name("_id") string id;
	Timestamp creation;
	Timestamp start;
	Timestamp finish;
	long pendingJobs;
	long executingJobs;
	long completedJobs;
	int success;
	int failed;
	int unknown;
	this(JobTrigger t, string tId, int p = 0)
	{
		trigger = t;
		triggerId = tId;
		priority = p;
		id = sha1Of(t.to!string ~ tId).toHexString().text;
		creation = getTimestamp();
	}
	int opCmp(ref const JobSet other)
	{
		import std.algorithm : cmp;
		auto r1 = priority - other.priority;
		if (r1 != 0)
			return r1;
		if (creation < other.creation)
			return -1;
		if (creation > other.creation)
			return 1;
		return 0;
	}
	string toString() const
	{
		import std.format : format;
		final switch (trigger)
		{
			case JobTrigger.DmdRelease: return format("Dmd release (%s)",triggerId);
			case JobTrigger.PackageUpdate: return format("Package update (%s)",triggerId);
			case JobTrigger.Manual: return format("Manual trigger");
			case JobTrigger.DmdPullRequest: return format("Dmd Pull request (%s)",triggerId);
			case JobTrigger.DruntimePullRequest: return format("Druntime Pull request (%s)",triggerId);
			case JobTrigger.PhobosPullRequest: return format("Phobos Pull request (%s)",triggerId);
			case JobTrigger.Nightly: return format("Nightly dmd (%s)",triggerId);
		}
	}
}
@("JobSet")
unittest{
	import std.stdio;
	import std.format;
	auto js = JobSet(JobTrigger.DmdRelease,"v2.071.2-b2",40);
	assert(format("%s",js) == "Dmd release (v2.071.2-b2)");
	assert(js.id == "A0BBDFBE633F974B5D0405C92397DB44F71A746F");
}
class JobScheduler
{
	private Job[] jobs;
	private JobSet[] sets;
	Nullable!Job getJob()
	{
		auto n = Nullable!(Job)();
		if (jobs.length > 0)
		{
			n = jobs[0];
			jobs = jobs[1..$];
		}
		return n;
	}
	Nullable!Job getJob(bool delegate(Job) pred)
	{
		auto idx = jobs.countUntil!(j=>pred(j));
		if (idx == -1)
			return Nullable!Job();
		Job j = jobs[idx];
		jobs.remove(idx);
		jobs = jobs[0..$-1];
		return Nullable!Job(j);
	}
	Nullable!JobSet getHighPrioJobSet()
	{
		auto idx = sets.retro.countUntil!(s=>s.pendingJobs != 0);
		if (idx == -1)
			return Nullable!(JobSet)();
		return Nullable!(JobSet)(sets.retro[idx]);
	}
	void updateJobSet(JobSet js)
	{
		auto idx = sets.countUntil!(a=>a.id==js.id);
		if (idx == -1)
			return;
		bool reSort = sets[idx].priority != js.priority;
		sets[idx] = js;
		if (reSort)
			sort(sets);
	}
	Nullable!JobSet getJobSet(string id)
	{
		auto idx = sets.countUntil!(j=>j.id == id);
		if (idx == -1)
			return Nullable!JobSet();
		return Nullable!(JobSet)(sets[idx]);
	}
	void removeJobSet(string id)
	{
		auto idx = sets.countUntil!(j=>j.id == id);
		if (idx == -1)
			return;
		sets.remove(idx);
		sets = sets[0..$-1];
	}
	void restore(Job[] jobs, JobSet[] sets)
	{
		this.jobs = jobs;
		this.sets = sets;
		sort(this.sets);
	}
	void addJobs(Job[] jobs, JobSet js)
	{
		this.jobs ~= jobs;
		this.sets ~= js;
		sort(this.sets);
	}
}
@("JobScheduler")
unittest
{
	auto s = new JobScheduler();
	auto js = JobSet(JobTrigger.DmdRelease,"v2.071.1");
	auto dmds = [DmdVersion("v2.071.1","2012-12-12T08:33:12Z")];
	auto packages = [DubPackage("abc","0.1.1")];
	auto jobs = createJobs(dmds,packages,js).array();
	js.pendingJobs = jobs.length;
	s.addJobs(jobs,js);
	assert(!s.getHighPrioJobSet().isNull);
	assert(s.getHighPrioJobSet() == js);
	js.pendingJobs = 0;
	s.updateJobSet(js);
	assert(s.getHighPrioJobSet().isNull);
	js.pendingJobs = 1;
	s.updateJobSet(js);
	assert(!s.getHighPrioJobSet().isNull);
	assert(s.getHighPrioJobSet.pendingJobs == 1);
	s.removeJobSet(js.id);
	assert(s.getHighPrioJobSet().isNull);
}
auto createJobs(DmdVersions,DubPackages)(DmdVersions dmds, DubPackages packages, JobSet js)
{
	import std.algorithm : cartesianProduct;
	return dmds.cartesianProduct(packages).map!((t){
		auto sha = sha1Of(t[0].id ~ t[1]._id).toHexString().text;
		return Job(sha,t[0],t[1],js.id,js.trigger,js.triggerId,getTimestamp(),getTimestamp());
	});
}
struct JobSummary
{
	@name("_id") string id;
	DmdVersion dmd;
	DubPackage pkg;
	Timestamp start;
	Timestamp finish;
	ErrorStats result;
}
struct JobComparison
{
	JobSummary left;
	JobSummary right;	
}
bool isPullRequest(JobSet js)
{
	final switch(js.trigger)
	{
		case JobTrigger.DmdRelease:
		case JobTrigger.PackageUpdate:
		case JobTrigger.Manual:
  case JobTrigger.Nightly:
			return false;
		case JobTrigger.DmdPullRequest:
		case JobTrigger.DruntimePullRequest:
		case JobTrigger.PhobosPullRequest:
			return true;
	}
}
string getPullRequestRepo(JobSet js)
{
	final switch(js.trigger)
	{
		case JobTrigger.DmdRelease:
		case JobTrigger.PackageUpdate:
		case JobTrigger.Manual:
		case JobTrigger.Nightly:
			assert(false,"Can only create dmd version for pull requests");
		case JobTrigger.DmdPullRequest: return "dmd";
		case JobTrigger.DruntimePullRequest: return "druntime";
		case JobTrigger.PhobosPullRequest: return "phobos";
	}
}
bool doesPullRequestsExists(JobSet js)
{
	assert(js.isPullRequest);
	string repo = js.getPullRequestRepo();
	bool exists;
	requestHTTP("/repos/dlang/"~repo~"/pulls/"~js.triggerId,(scope req){
		req.method = HTTPMethod.GET;
	},(scope res){
		scope (exit) res.dropBody();
		if (res.statusCode == 404)
			exists = false;
		else if (res.statusCode != 200)
			throw new Exception("Invalid response");
		exists = true;
	});
	return exists;
}
JobComparison[] compareJobSummaries(JobSummary[] setA, JobSummary[] setB)
{
	auto compareJobSummary(JobSummary a, JobSummary b)
	{
		return cmp(a.pkg._id,b.pkg._id);
	}

	sort!((a,b)=>compareJobSummary(a,b)<0)(setA);
	sort!((a,b)=>compareJobSummary(a,b)<0)(setB);

	auto compsApp = appender!(JobComparison[]);
	while(!setA.empty && !setB.empty)
	{
		auto left = setA.front();
		auto right = setB.front();
		auto c = compareJobSummary(left,right);
		if (c == 0)
		{
			if (left.error.type != right.error.type ||
				left.error.exitCode != right.error.exitCode)
				compsApp.put(JobComparison(left,right));
			setA.popFront();
			setB.popFront();
		} else if (c < 0)
			setA.popFront();
		else
			setB.popFront();
	}
	return compsApp.data;
}
@("compareJobSummaries")
unittest
{
	auto dmd = DmdVersion("v2.061.1","2012-12-12T08:33:12Z");
	auto pkgs = [DubPackage("abc","1.0.0"),DubPackage("def","1.0.0")];
	auto noError = ErrorStats(ErrorType.None);
	auto linkerError = ErrorStats(ErrorType.LinkerError);
	auto dmdError1 = ErrorStats(ErrorType.DmdNonZeroExit,1);
	auto dmdError99 = ErrorStats(ErrorType.DmdNonZeroExit,99);

	auto sum0noError = JobSummary("",dmd,pkgs[0],getTimestamp,getTimestamp,noError);
	auto sum1noError = JobSummary("",dmd,pkgs[1],getTimestamp,getTimestamp,noError);
	auto sum0linkerError = JobSummary("",dmd,pkgs[0],getTimestamp,getTimestamp,linkerError);
	auto sum0dmd1Error = JobSummary("",dmd,pkgs[0],getTimestamp,getTimestamp,dmdError1);
	auto sum0dmd99Error = JobSummary("",dmd,pkgs[0],getTimestamp,getTimestamp,dmdError99);

	import std.algorithm : equal;
	assert(compareJobSummaries([sum0noError],[sum0noError]).empty);
	assert(compareJobSummaries([sum0noError,sum1noError],[sum1noError]).empty);
	assert(compareJobSummaries([sum0noError,sum1noError],[sum1noError,sum0linkerError]).equal(
		[JobComparison(sum0noError,sum0linkerError)])
	);
	assert(compareJobSummaries([sum0linkerError,sum1noError],[sum1noError,sum0linkerError]).empty);

	assert(compareJobSummaries([sum0dmd1Error],[sum0dmd99Error]).equal(
		[JobComparison(sum0dmd1Error,sum0dmd99Error)])
	);
}
