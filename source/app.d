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
import dubster.docker;
import dubster.worker;
import dubster.server;
import dubster.reporter;
import dubster.analyser;
import dubster.persistence;

import vibe.core.log : logInfo;
import std.process : environment;
import vibe.inet.url : URL;
import vibe.core.core : runTask, runEventLoop;
import vibe.web.rest : RestInterfaceClient;
import vibe.http.server : HTTPServerSettings;
import vibe.core.args : readOption, finalizeCommandLineOptions, printCommandLineHelp;
import vibe.db.mongo.mongo : connectMongoDB;

void main()
{
  logInfo("Starting Dubster");
	auto settings = readSettings();
	if (!settings.validate())
		return printCommandLineHelp();
	if (!finalizeCommandLineOptions())
		return;

	runTask({
    if (settings.worker) {
      logInfo("Starting Worker");
      new Worker(settings.createWorkerSettings);
    } else if (settings.server)
		{
      logInfo("Starting Persistence Layer");
			auto db = new Persistence(connectMongoDB(settings.mongoHost).getDatabase(settings.mongoDb));
      logInfo("Starting Migration Layer");
			auto migrator = db.migrator();

			if (migrator.needsMigration)
			{
				if (!settings.allowMigration)
					throw new Exception("System needs migration but program not started with --migrate flag. Please ***backup db*** and rerun with --migrate flag.");
        logInfo("Starting Migration");
				migrator.migrate();
			}
      auto reporter = new Reporter();
      logInfo("Starting Server");
			new Server(settings.createServerSettings, db, reporter);
    }
	});

	runEventLoop();
}
WorkerSettings createWorkerSettings(Settings settings)
{
	return WorkerSettings(
		new RestInterfaceClient!IDubsterApi(settings.serverHost),
		new DockerClient(),
		settings.memoryLimit
	);
}
ServerSettings createServerSettings(Settings settings)
{
	auto sSettings = new HTTPServerSettings();
	sSettings.port = 8080;
	sSettings.maxRequestSize = 10 * 1024 * 1024;
	sSettings.useCompressionIfPossible = true;
	return ServerSettings(sSettings,settings.doSync);
}
struct Settings
{
	bool worker = false;
	bool server = false;
	bool analyser = false;
	bool doSync = true;
	bool allowMigration = false;
	URL serverHost;
	long memoryLimit;
	string mongoHost, mongoUser, mongoPass, mongoDb;
}
Settings readSettings()
{
	Settings settings;
	string host;
	if (readOption("worker",&settings.worker,"Starts a worker"))
	{
		if (readOption("serverHost",&host,"Public address of server"))
			settings.serverHost = URL(host);
		readOption("memory",&settings.memoryLimit,"Memory limit of container");
		if (settings.memoryLimit < 1024*1024*1024)
			throw new Exception("Too little memory for container, must be over 1Gb.");
	}
	if (readOption("server",&settings.server,"Starts a server"))
	{
		settings.mongoHost = environment.get("MONGO_PORT_27017_TCP_ADDR", "127.0.0.1");
		settings.mongoDb = environment.get("MONGO_DB_NAME", "dubster");
		readOption("mongoHost",&settings.mongoHost,"MongoDB address (default 127.0.0.1)");
		readOption("mongoUser",&settings.mongoUser,"MongoDB user");
		readOption("mongoPass",&settings.mongoPass,"MongoDB pass");
		readOption("mongoDb",&settings.mongoPass,"MongoDB Database name (default dubster)");
		readOption("sync",&settings.doSync,"Sync known dmd releases from github and packages from code.dlang.org and create build jobs for them (default: true)");
		readOption("migrate",&settings.allowMigration,"Allow db migrations");
	}
	return settings;
}
bool validate(Settings settings)
{
	auto total = cast(int)settings.worker + cast(int)settings.analyser + cast(int)settings.server;
	if (total != 1)
		return false;
	if (settings.worker && settings.serverHost.host.length == 0)
		return false;
	if (settings.server)
	{
		if (settings.mongoHost.length == 0)
			return false;
	}
	return true;
}
