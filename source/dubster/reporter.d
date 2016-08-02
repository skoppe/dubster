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
module dubster.reporter;

import dubster.job;
import dubster.server;
import std.stdio;

alias Timestamp = long;
Timestamp getTimestamp()
{
	return Clock.currStdTime();
}
struct JobExecuting
{
	Job job;
	Timestamp timestamp;
}
struct JobComplete
{
	JobResult results;
	Timestamp timestamp;
}
interface IReporter
{
	void executing(Job job);
	void complete(JobResult results);
}
class Reporter : IReporter
{
	void executing(Job job)
	{
		writeln("Executing Job: ",job);
	}
	void complete(JobResult results)
	{
		writeln("Completed Job: ",results);
	}
}