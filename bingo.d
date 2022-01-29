// FIXME: timestamp on messages should be prettier
// FIXME: color usernames in chat and mark the room creator with an icon
// FIXME: don't show opponent's selection until locked in
// FIXME: let people star rows they intend to do for their own view

module ffr_bingo.main;

import ffr_bingo.card;
import ffr_bingo.randomizer;

import arsd.cgi;
import arsd.webtemplate;
import arsd.sqlite;
import arsd.dom;

import std.conv;

alias POST = Cgi.RequestMethod.POST;

enum RoomFormat {
	OneVsOne,
	OpenGroup
}

void importSet(Sqlite db, string name, string description, string created_by, string text) {
	import ffr_bingo.data_importer;

	db.query("INSERT INTO square_sets (name, description, created_by) VALUES (?, ?, ?)", name, description, created_by);

	auto ssid = db.lastInsertId;

	foreach(square; importText(text)) {
		db.query("INSERT INTO
			squares
			(name, details, easiness, how_common, starts_game_checked, mutex_group)
			VALUES
			(?, ?, ?, ?, ?, ?)",
			square.name, square.details, square.easiness, square.how_common, square.starts_game_checked, square.mutex_group);
		db.query("INSERT INTO square_set_members (square_set_id, square_id) VALUES (?, ?)", ssid, db.lastInsertId);
	}

}

Sqlite getDatabase() {
	import std.string;
	static Sqlite db;
	if(db is null)
		db = openDBAndCreateIfNotPresent("bingo.db", import("db.sql").replace("SERIAL", "INTEGER"), (db) {
			import std.file;
			importSet(db, "2020-2021 Winter DAB", "The bingo squares used for the 2020-2021 tournament.", null, readText("data-2020.txt"));
			importSet(db, "2021-2022 Winter DAB", "The bingo squares used for the 2021-2022 tournament held in February 2022.", null, readText("data-2021.txt"));
		});
	return db;
}

Square[] loadSquareSet(int id) {
	Square[] set;
	foreach(row; getDatabase().query("SELECT squares.* FROM squares INNER JOIN square_set_members ON square_id = squares.id WHERE square_set_id = ?", id)) {
		auto square = new Square(row.toAA);

		set ~= square;
	}
	return set;
}

struct User {
	int id;
	string name;

	string selection;

	static User active(Cgi cgi) {
		if(auto ptr = "sessionId" in cgi.cookies) {
			foreach(row; getDatabase().query("SELECT id, display_name FROM users INNER JOIN login_sessions ON user_id = users.id WHERE session_id = ?", *ptr))
				return User(row["id"].to!int, row["display_name"]);

		}
		return User.init;
	}

	static User load(int id) {
		foreach(row; getDatabase().query("SELECT id, display_name FROM users WHERE id = ?", id))
			return User(row["id"].to!int, row["display_name"]);

		return User.init;
	}

	static User getAutomaticallyForCgi(Cgi cgi) {
		return User.active(cgi);
	}
}

struct HomeInfo {
	string[string][] rooms;
	User user;

	string[string][] square_sets;
}

class Bingo : WebObject {
	@UrlName("")
	@Template("home.html")
	HomeInfo home(User user) {
		string[string][] ret;
		foreach(row; getDatabase().query("SELECT * FROM rooms where closed_at is null"))
			ret ~= row.toAA;

		string[string][] square_sets;
		foreach(row; getDatabase().query("
			SELECT
				square_sets.id,
				square_sets.name,
				users.display_name AS creator_name
			FROM
				square_sets
			LEFT OUTER JOIN
				users ON square_sets.created_by = users.id
			WHERE
				square_sets.id > 2
		"))
			square_sets ~= row.toAA;

		return HomeInfo(ret, user, square_sets);
	}

	@AutomaticForm
	@POST
	Redirection importSquareSet(User user, string name, Cgi.UploadedFile squaresTxt) {
		if(user.id == 0)
			throw new Exception("you aren't logged in");
		importSet(getDatabase(), name, "", to!string(user.id), cast(string) squaresTxt.content);
		return Redirection("/");
	}

	@AutomaticForm
	@POST
	Redirection createRoom(User user, string name, RoomFormat roomFormat, int squareSetId, bool ignoreRarity, bool ignoreDifficulty, uint seed = 0) {
		auto db = getDatabase();
		db.query("INSERT INTO rooms (name, seed, flags, square_set_id, format, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)",
			name,
			0,
			(ignoreRarity ? 1:0) | (ignoreDifficulty ? 2:0),
			squareSetId,
			cast(int) roomFormat,
			user.id
		);

		auto room = new Room(db.lastInsertId.to!string);
		room.newSeed(seed);

		return Redirection(room.url);
	}

	@UrlName("squares.txt")
	void squaresText(Cgi cgi) {
		cgi.setResponseContentType("text/plain");
		cgi.write(import("data-2021.txt"), true);
	}

	Square[] squares() {
		return loadSquareSet(2);
	}

	Redirection login(Cgi cgi) {

		cgi.setCookie("postLoginRedirect", cgi.referrer, 0, "/", null, true, cgi.https);

		import std.file, arsd.jsvar;
		var info = var.fromJson(readText("discord.json"));
		return Redirection(info.authorize_url.get!string);
	}
	Redirection discord(Cgi cgi, string code/*, string state */) {
		import arsd.http2;
		import std.file, arsd.jsvar;
		var info = var.fromJson(readText("discord.json"));
		auto response = post("https://discord.com/api/oauth2/token", [
			"client_id": info.client_id.get!string,
			"client_secret": info.client_secret.get!string,
			"grant_type": "authorization_code",
			"code": code,
			"redirect_uri": "http://adamdruppe.com:8080/discord"
		]).waitForCompletion;

		if(response.code >= 200 && response.code < 300) {
			var r = var.fromJson(response.responseText);

			auto at = r["access_token"].get!string;
			if(at.length == 0)
				throw new Exception("no access token in " ~ response.responseText);

			import std.uri;
			auto req = get("https://discord.com/api/users/@me");
			req.requestParameters.authorization = "Bearer " ~ at;
			var answer = var.fromJson(req.waitForCompletion.responseText);

			auto db = getDatabase();
			auto discordUsername = answer.username.get!string;
			auto discordId = answer.id.get!string;

			int localId;

			auto result = db.query("SELECT id, display_name FROM users WHERE username = ?", discordId);
			if(result.empty) {
				db.query("INSERT INTO users (display_name, username, access_type, access_code) VALUES (?, ?, ?, ?)",
					discordUsername, discordId, 1, "");

				localId = db.lastInsertId;
			} else {
				auto row = result.front;
				localId = row["id"].to!int;
				if(discordUsername != row["display_name"]) {
					db.query("UPDATE users SET display_name = ? WHERE id = ?", discordUsername, localId);
				}
			}

			import std.random;
			long sessionId = uniform(1, long.max);

			// I'm doing the sessions in the database instead of using the library facility
			// just because in testing deleting the database will happen often...
			db.query("INSERT INTO login_sessions (session_id, user_id) VALUES (?, ?)", sessionId, localId);
			cgi.setCookie("sessionId", sessionId.to!string, 0, "/", null, true, cgi.https);

			string redirectTo = "/";
			if("postLoginRedirect" in cgi.cookies) {
				redirectTo = cgi.cookies["postLoginRedirect"];
				cgi.setCookie("postLoginRedirect", null, 0, "/", null, true, cgi.https);

				auto uri = Uri(redirectTo);
				redirectTo = uri.path;

				if(redirectTo.length < 1 || redirectTo[0] != '/')
					redirectTo = "/";
			}

			return Redirection(redirectTo);

		} else throw new Exception(response.responseText);
	}

	@AutomaticForm
	@POST
	Redirection becomeGuest(Cgi cgi, string name) {
		import std.random;
		auto db = getDatabase();
		db.query("INSERT INTO users (display_name, username, access_type, access_code) VALUES (?, ?, ?, ?)",
			name, uniform(1000, int.max), 2, "");

		long sessionId = uniform(1, long.max);
		db.query("INSERT INTO login_sessions (session_id, user_id) VALUES (?, ?)", sessionId, db.lastInsertId);
		cgi.setCookie("sessionId", sessionId.to!string, 0, "/", null, true, cgi.https);

		return Redirection("/");
	}
}

class Room : WebObject {
	private string essName;

	private string name;
	private uint seed;
	private bool ignoreRarity;
	private bool ignoreDifficulty;
	private int square_set_id;

	private User[] players;
	private string[] player_selections;

	private int id;
	private int created_by;

	private bool closed;
	private bool locked_in;

	private long initialClockTicks;
	private bool clockRunning;

	private RoomFormat roomFormat;

	private Redirection reload() {
		return Redirection("../" ~ to!string(id) ~ "/");
	}

	private string url() {
		return "/room/" ~ to!string(id) ~ "/";
	}

	this(string id) {
		auto db = getDatabase();
		auto result = db.query("SELECT * FROM rooms WHERE id = ?", id);
		if(result.empty)
			throw new ResourceNotFoundException("room", id);

		auto row = result.front;

		this.name = row["name"];
		this.seed = row["seed"].to!uint;
		this.id = row["id"].to!int;
		auto flags = row["flags"].to!uint;
		this.ignoreDifficulty = (flags & 2) ? true : false;
		this.ignoreRarity = (flags & 1) ? true : false;
		this.square_set_id = row["square_set_id"].to!int;
		this.created_by = row["created_by"].to!int;
		this.closed = row["closed_at"].length > 0;
		this.locked_in = row["locked_in"] == "1" ? true : false;

		if(row["clock_ticks"].length)
			this.initialClockTicks = row["clock_ticks"].to!long;
		if(row["clock_started"].length) {
			long clock_started = row["clock_started"].to!long;
			auto ticksElapsed = ((MonoTime.currTime.ticks - clock_started) / (MonoTime.ticksPerSecond / 1000));
			this.initialClockTicks += ticksElapsed;
			this.clockRunning = true;
		}

		this.roomFormat = cast(RoomFormat) row["format"].to!int;

		if(this.closed)
			this.locked_in = true;

		foreach(player; db.query("SELECT * FROM room_players WHERE room_id = ? ORDER BY player_number", id)) {
			// FIXME: n+1 nonsense again
			players ~= User.load(player["player_id"].to!int);
			players[$-1].selection = player["challenge_selection"];
			player_selections ~= player["challenge_selection"];

		}

		this.essName = "ffr_bingo/" ~ row["id"];
	}

	@POST
	void sendChat(User currentUser, string message) {
		if(currentUser.id)
			recordEvent(currentUser, EventType.chat_message, message);
		else
			throw new Exception("You aren't logged in.");
	}

	private int playerNumber(User who) {
		int playerNumber = -1;
		foreach(number, player; players)
			if(player.id == who.id) {
				playerNumber = cast(int) number;
				break;
			}
		return playerNumber;
	}

	@POST
	void assignOpponentChallenge(User currentUser, string challenge) {
		if(this.locked_in)
			throw new Exception("The room is already locked.");
		if(currentUser.id == 0)
			throw new Exception("You aren't logged in.");

		if(playerNumber(currentUser) == -1)
			throw new Exception("You aren't a player in the room.");

		auto db = getDatabase();

		db.query("UPDATE room_players SET challenge_selection = ? WHERE room_id = ? AND player_id = ?", challenge, id, currentUser.id);

		var info = var.emptyObject;
		info.player_id = currentUser.id;

		recordEvent(currentUser, EventType.set_challenge, info.toJson());
	}

	@POST
	void resetClock(User who, int countdown = 0) {
		auto db = getDatabase();

		auto ticks = -countdown * 1000;
		db.query("UPDATE rooms SET clock_ticks = ?, clock_started = null WHERE id = ?", ticks, id);

		var info = var.emptyObject;

		info.state = "paused";
		info.time = ticks;

		sendClockUpdate(ticks, 0);

		recordEvent(who, EventType.clock_reset, info.toJson());
	}

	@POST
	void toggleClock(User who) {
		import core.time;
		auto db = getDatabase();

		long clock_started;
		long clock_ticks;

		foreach(row; db.query("SELECT clock_started, clock_ticks FROM rooms WHERE id = ?", id)) {
			if(row["clock_ticks"].length)
				clock_ticks = std.conv.to!long(row["clock_ticks"]);
			if(row["clock_started"].length)
				clock_started = std.conv.to!long(row["clock_started"]);
		}

		var info = var.emptyObject;

		if(clock_started) {
			// already running, just pause it
			auto ticksElapsed = ((MonoTime.currTime.ticks - clock_started) / (MonoTime.ticksPerSecond / 1000));
			db.query("UPDATE rooms SET clock_started = null, clock_ticks = clock_ticks + ? WHERE id = ?", ticksElapsed, id);

			info.state = "paused";
			info.time = clock_ticks + ticksElapsed;
		} else {
			db.query("UPDATE rooms SET clock_started = ? WHERE id = ?", MonoTime.currTime.ticks, id);

			info.state = "running";
			info.time = clock_ticks;
		}

		recordEvent(who, EventType.clock, info.toJson());
	}

	private void sendClockUpdate(long ticks, bool running) {
		var msg = var.emptyObject;
		msg.state = running;
		msg.time = ticks;
		EventSourceServer.sendEvent(essName, "clock_update", msg.toJson(), 0);
	}

	private void sendClockUpdate() {
		sendClockUpdate(initialClockTicks, clockRunning);
	}

	@POST
	void toggleSquare(User player, int squareId) {
		var v = var.emptyObject;
		v.squareId = squareId;

		if(player.id == 0)
			throw new Exception("You aren't logged in");

		auto playerNumber = this.playerNumber(player);
		if(playerNumber == -1)
			throw new Exception("You aren't a registered player in the room");

		auto db = getDatabase();

		v.square = db.queryOneColumn!string("SELECT name FROM squares WHERE id = ?", squareId);
		v.player = playerNumber;

		auto playerMask = 1 << playerNumber;

		// omg why does sqlite not have ^
		// i wish my version of sqlite supported RETURNING like postgres. alas it too new
		db.query("UPDATE room_squares SET player_checked_state = ((player_checked_state & ~?) | ((~player_checked_state) & ?)) WHERE room_id = ? AND square_id = ?", playerMask, playerMask, id, squareId);

		EventType et;

		et = (db.queryOneColumn!int("SELECT player_checked_state FROM room_squares WHERE room_id = ? AND square_id = ?", id, squareId) & playerMask) ? EventType.set : EventType.unset;

		recordEvent(player, et, v.toJson());
	}

	@POST
	Redirection joinGame(User user) {
		if(user.id == 0)
			return Redirection("/login");

		auto db = getDatabase();

		// FIXME: if player already in don't rejoin them

		db.query("INSERT INTO room_players (room_id, player_id, challenge_selection, player_number) VALUES (?, ?, null, (
			SELECT count(*) FROM room_players WHERE room_id = ?
		))", id, user.id, id);

		import std.conv;
		recordEvent(user, EventType.joined, "as player " ~ to!string(players.length + 1)); // FIXME

		// FIXME
		if(0) {
			throw new Exception("Sorry, room full.");
		}

		return reload;
	}

	@POST
	Redirection leaveGame(User currentUser, int playerId) {
		auto db = getDatabase();

		if(locked_in)
			throw new Exception("Room locked in, can't leave");
		if(currentUser.id != created_by && playerId != currentUser.id)
			throw new Exception("Permission denied");

		db.query("DELETE FROM room_players WHERE room_id = ? AND player_id = ?", id, playerId);

		import std.conv;
		recordEvent(currentUser, EventType.quit, " player " ~ to!string(playerId));

		return reload;
	}

	@POST
	Redirection shufflePlayers(User user) {
		auto db = getDatabase();

		import std.random;

		// FIXME: race condition
		int idx;
		foreach(player; randomCover(players)) {
			db.query("UPDATE room_players SET player_number = ? WHERE player_id = ? AND room_id = ?", idx, player.id, id);
			idx++;
		}

		recordEvent(user, EventType.swapped, null);

		return reload;
	}

	@POST
	Redirection swapPlayers(User user) {
		// FIXME
		auto db = getDatabase();
		db.query("UPDATE rooms SET
			player_one = player_two, player_two = player_one,
			player_one_selection = player_two_selection, player_two_selection = player_one_selection
			where id = ?", id);

		recordEvent(user, EventType.swapped, null);

		return reload;
	}

	@POST
	Redirection newSeed(User user) {
		newSeed(0);

		recordEvent(user, EventType.new_seed, ""); //  card.toHtml().toString());
		return reload;
	}

	@POST
	Redirection closeRoom(User user) {
		if(user.id == created_by) {
			getDatabase().query("UPDATE rooms SET closed_at = CURRENT_TIMESTAMP where id = ?", id);
			recordEvent(user, EventType.room_closed, "");
		} else {
			throw new Exception("permission denied");
		}

		return Redirection("/");
	}

	private void newSeed(uint seed) {
		import std.random;
		this.seed = seed = seed ? seed : unpredictableSeed;

		auto db = getDatabase();

		db.startTransaction;
		scope(failure) db.query("ROLLBACK");

		db.query("UPDATE rooms SET seed = ? WHERE id = ?", this.seed, id);
		db.query("DELETE FROM room_squares WHERE room_id = ?", id);

		auto card = createRandomCard(loadSquareSet(square_set_id), this.seed, ignoreRarity, ignoreDifficulty);

		foreach(pos, square; card) {
			db.query("INSERT INTO room_squares (room_id, square_id, position, player_checked_state) VALUES (?, ?, ?, 0)",
				id, square.id, cast(int) pos);
		}

		db.query("COMMIT");
	}

	@POST
	Redirection lockIn(User user) {
		// FIXME: until the room is locked in, the challenge row selection should not be visible to the other player

		getDatabase().query("UPDATE rooms SET locked_in = true WHERE id = ?", id);
		recordEvent(user, EventType.lock_in, "");
		return reload;
	}

	//
	void eventStream(Cgi cgi) {
		EventSourceServer.adoptConnection(cgi, essName);
	}

	private Element feedHtml(User who, string createdAt, string inGameTime, EventType eventType, string eventMessage) {
		string message;

		bool preferGameClock;

		final switch(eventType) {
			case EventType.NULL:
			break;
			case EventType.new_seed:
				message = who.name ~ " reset the seed";
			break;
			case EventType.lock_in:
				message = who.name ~ " locked in the game settings";
			break;
			case EventType.joined:
				message = who.name ~ " joined " ~ eventMessage;
			break;
			case EventType.quit:
				message = who.name ~ " is no longer " ~ eventMessage;
			break;
			case EventType.set:
				var o = var.fromJson(eventMessage);
				message = who.name ~ " set square " ~ o.square.get!string;
				preferGameClock = true;
			break;
			case EventType.unset:
				var o = var.fromJson(eventMessage);
				message = who.name ~ " unset square " ~ o.square.get!string;
				preferGameClock = true;
			break;
			case EventType.chat_message:
				message = who.name.htmlEntitiesEncode ~ ": " ~ eventMessage.htmlEntitiesEncode;
			break;
			case EventType.set_challenge:
				message = who.name ~ " chose a challenge";
			break;
			case EventType.room_closed:
				message = who.name.htmlEntitiesEncode ~ " closed the room.";
			break;
			case EventType.swapped:
				message = "Players just swapped colors at "~who.name.htmlEntitiesEncode~"'s request.";
			break;
			case EventType.clock_reset:
				message = "Clock reset";
			break;
			case EventType.clock:
				var o = var.fromJson(eventMessage);
				message = "Clock " ~ o.state.get!string;
			break;
		}

		auto e = Element.make("div", "", eventType.to!string);
		if(createdAt.length > 11) {
			import std.datetime, std.conv;
			SysTime time = SysTime(DateTime(
				createdAt[0 .. 4].to!int,
				createdAt[5 .. 7].to!int,
				createdAt[8 .. 10].to!int,
				createdAt[11 .. 13].to!int,
				createdAt[14 .. 16].to!int,
				createdAt[17 .. 19].to!int,
			), UTC());
			createdAt = time.toLocalTime().toSimpleString();

			if(preferGameClock && inGameTime.length && inGameTime != "0") {
				import std.format;
				auto seconds = to!long(inGameTime) / 1000;
				bool negative = seconds < 0;
				if(negative)
					seconds = -seconds;
				auto minutes = seconds / 60;
				seconds = seconds % 60;
				auto hours = minutes / 60;
				minutes = minutes % 60;
				e.addChild("span", format("%s%d:%02d:%02d", negative ? "-":"+", hours, minutes, seconds), "timestamp");
			} else {
				e.addChild("time", createdAt.length > 11 ? createdAt[11 .. 20] : null, "timestamp").setAttribute("datetime", time.toISOExtString());
			}

			e.appendText(" ");
		}
		e.appendHtml(message);
		return e;
	}

	private void recordEvent(User who, EventType eventType, string eventMessage, bool send = true) {
		auto db = getDatabase();
		db.query("INSERT INTO room_feed (room_id, actor, type, message, in_game_time, created_at) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)",
			id, who.id, eventType, eventMessage, initialClockTicks);

		if(!send)
			return;

		var msg = var.emptyObject;

		msg.eventMessage = eventMessage;
		msg.feedHtml = feedHtml(who, db.query("SELECT CURRENT_TIMESTAMP").front[0], to!string(initialClockTicks), eventType, eventMessage);

		EventSourceServer.sendEvent(essName, eventType.to!string, msg.toJson(), 0);
	}

	Element[] feedHtml() {
		Element[] ret;
		// FIXME: do a proper join instead of n+1 bs
		foreach(row; getDatabase().query("SELECT * FROM room_feed WHERE room_id = ?", id))
			ret ~= feedHtml(User.load(row["actor"].to!int), row["created_at"], row["in_game_time"], row["type"].to!EventType, row["message"]);

		return ret;
	}

	static struct RoomHome {
		int id;
		string name;
		Element card_html;
		Element[] feed_html;

		User current_user;

		bool can_edit;
		bool locked_in;
		bool closed;
		bool can_join;

		User[] players;

		int current_player_number;

		uint seed;

		RoomFormat roomFormat;

		User created_by;

		long clockTicks;
		bool clockRunning;
	}

	@UrlName("")
	@Template("room.html")
	RoomHome home(User currentUser) {
		import std.random;
		import std.file;

		bool can_join;

		if(!locked_in) {
			if(currentUser.id) {
				if(playerNumber(currentUser) == -1) {
					if(roomFormat == RoomFormat.OpenGroup) {
						// always room here unless locked
						can_join = true;
					} else if(roomFormat == RoomFormat.OneVsOne) {
						can_join = players.length < 2;
					}
				} else {
					// already in, can't join again
				}
			} else {
				// not logged in, can't join
			}
		} else {
			// can't join a locked in room
		}

		return RoomHome(
			id,
			name,
			this.card(currentUser).toHtml(),
			feedHtml,

			currentUser,

			!closed && currentUser.id == created_by, // can_edit
			locked_in, // locked_in
			closed, // closed
			can_join,
			//!locked_in && !closed && currentUser.id != 0 && (player_one.id == 0 || player_two.id == 0) && (player_one.id != currentUser.id && player_two.id != currentUser.id), // can_join

			players,

			// current_player_number
			playerNumber(currentUser),

			seed,

			roomFormat,
			User.load(created_by),

			initialClockTicks,
			clockRunning
		);
	}

	Card card(User who) {
		auto card = new Card();

		auto cp = playerNumber(who);
		foreach(idx, s; player_selections) {
			if(locked_in || idx == cp)
				card.player_selections ~= s;
			else
				card.player_selections ~= ""; // private until locked in
		}

		auto db = getDatabase();
		int pos;
		foreach(row; db.query("
			SELECT
				squares.*, player_checked_state
			FROM
				squares
			INNER JOIN
				room_squares ON square_id = squares.id
			WHERE
				room_id = ?
			ORDER BY
				position
		", id))
		{
			card[pos++] = new InGameSquare(row.toAA);
		}

		return card;
	}

	enum EventType {
		NULL,
		new_seed,
		lock_in,
		chat_message,
		joined,
		quit,
		set,
		unset,
		set_challenge,
		room_closed,
		swapped,
		clock,
		clock_reset
	}
}

class Presenter : WebPresenterWithTemplateSupport!Presenter {}

mixin DispatcherMain!(Presenter,
	"/assets/".serveStaticFileDirectory,
	"/room/".serveApi!Room,
	"/pages/".serveTemplateDirectory,
	"/".serveApi!Bingo,
);
