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
module dubster.analyser;

import dubster.server;
import vibe.d;

import std.algorithm : partition, canFind, map, joiner;
import std.conv : to, text;
import std.array : array;
import std.stdio : writefln, writeln;
import std.range : take;
import std.regex;

enum ErrorType:string
{
	None = "None",
	LinkerError = "LinkerError",
	DmdNonZeroExit = "DmdNonZeroExit",
	UnittestNonZeroExit = "UnittestNonZeroExit",
	Skipped = "Skipped",
	DubBuildErrors = "DubBuildErrors",
	Unknown = "Unknown"
}
struct ErrorStats
{
	ErrorType type;
	int exitCode;
	string details;
}
ErrorStats parseError(string results)
{
	if (results.canFind("All unit tests have been run successfully.\n") ||
		results.canFind("\nOK!\n"))
		return ErrorStats(ErrorType.None,0,"");

	auto linkErrorReg = ctRegex!`\/usr\/bin\/ld: cannot find -l\w+`;
	auto linkMatches = results.matchAll(linkErrorReg);
	if (linkMatches)
		return ErrorStats(ErrorType.LinkerError,1,linkMatches.map!("a.hit").joiner("\n").text());

	auto dmdExitReg = ctRegex!`\/dmd failed with exit code (-?[0-9]+)`;
	auto dmdExitMatch = results.matchFirst(dmdExitReg);
	if (dmdExitMatch)
		return ErrorStats(ErrorType.DmdNonZeroExit,dmdExitMatch[1].to!int,"");

	auto skipTestReg = ctRegex!`Configuration '[^']*' has target type "[^"]*". Skipping test.`;
	auto skipTestMatch = results.matchFirst(skipTestReg);
	if (skipTestMatch)
		return ErrorStats(ErrorType.Skipped,1,skipTestMatch.hit);

	auto programExitReg = ctRegex!`Program exited with code (-?[0-9]+)`;
	auto programExitMatch = results.matchFirst(programExitReg);
	if (programExitMatch)
		return ErrorStats(ErrorType.UnittestNonZeroExit,programExitMatch[1].to!int,"");

	auto dubErrorReg1 = ctRegex!`Non-optional dependency \w+:\w+ of \w+ not found in dependency tree!\?`;
	auto dubErrorMatch1 = results.matchFirst(dubErrorReg1);
	if (dubErrorMatch1)
		return ErrorStats(ErrorType.DubBuildErrors,1,dubErrorMatch1.hit);

	auto dubErrorReg2 = ctRegex!`Main package must have a binary target type, not \w+. Cannot build.`;
	auto dubErrorMatch2 = results.matchFirst(dubErrorReg1);
	if (dubErrorMatch2)
		return ErrorStats(ErrorType.DubBuildErrors,1,dubErrorMatch2.hit);

	auto dubErrorReg3 = ctRegex!`Failed to download https?:\/\/code.dlang.org[^ ]+: [3-5][0-9]{2}`;
	auto dubErrorMatch3 = results.matchFirst(dubErrorReg1);
	if (dubErrorMatch3)
		return ErrorStats(ErrorType.DubBuildErrors,1,dubErrorMatch3.hit);

	auto dubErrorReg4 = ctRegex!`No package file found in .+?, expected one of dub.json\/dub.sdl\/package.json`;
	auto dubErrorMatch4 = results.matchFirst(dubErrorReg1);
	if (dubErrorMatch4)
		return ErrorStats(ErrorType.DubBuildErrors,1,dubErrorMatch4.hit);

	return ErrorStats(ErrorType.Unknown,1,"");
}

unittest
{
	import std.stdio;
	auto error = "/usr/bin/ld: cannot find -levent\n/usr/bin/ld: cannot find -levent_pthreads".parseError;
	assert(error.type == ErrorType.LinkerError);
	assert(error.details == "/usr/bin/ld: cannot find -levent\n/usr/bin/ld: cannot find -levent_pthreads");
}