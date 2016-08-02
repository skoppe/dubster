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

import std.algorithm : countUntil, remove;
import std.datetime : Clock;
import std.typecons : Nullable;
import dubster.dub;
import dubster.dmd;

struct Job
{
	@name("_id") BsonObjectID id;
	DmdVersion dmd;
	DubPackage pkg;
}
class JobQueue
{
	private Job[] jobs;
	void addJob(Job job)
	{
		jobs ~= job;
	}
	auto popFirst(alias pred)()
	{
		auto idx = jobs.countUntil!pred;
		if (idx == -1)
			return Nullable!Job();
		Job j = jobs[idx];
		jobs.remove(idx);
		jobs = jobs[0..$-1];
		return Nullable!Job(j);
	}
}