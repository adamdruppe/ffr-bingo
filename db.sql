CREATE TABLE squares (
	id SERIAL PRIMARY KEY,
	name TEXT NOT NULL,
	details TEXT NOT NULL,
	easiness INTEGER NOT NULL,
	how_common INTEGER NOT NULL,
	starts_game_checked BOOLEAN NOT NULL,
	mutex_group TEXT NULL,

	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
	id SERIAL PRIMARY KEY,

	display_name TEXT NOT NULL,
	username TEXT NOT NULL UNIQUE,

	access_type INTEGER NOT NULL DEFAULT 0,
	access_code TEXT NOT NULL, -- depending on type can be a hashed password or a discord connection

	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE square_sets (
	id SERIAL PRIMARY KEY,
	name TEXT NOT NULL,
	description TEXT NOT NULL,
	created_by INTEGER NULL,

	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
);


CREATE TABLE login_sessions (
	session_id BIGINT UNIQUE,
	user_id INTEGER
);

CREATE TABLE rooms (
	id SERIAL PRIMARY KEY,
	name TEXT NOT NULL,

	seed INTEGER NOT NULL,
	flags INTEGER NOT NULL, -- ignore rarity etc.
	square_set_id INTEGER NOT NULL,

	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	closed_at TIMESTAMPTZ NULL, -- once it is closed, the game is over
	locked_in BOOLEAN NOT NULL DEFAULT FALSE,

	format INTEGER NOT NULL,

	created_by INTEGER NULL,

	clock_started INTEGER NULL,
	clock_ticks INTEGER NOT NULL DEFAULT 0,

	FOREIGN KEY(square_set_id) REFERENCES square_set_id(id) ON DELETE CASCADE ON UPDATE CASCADE,

	FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE room_players (
	id SERIAL PRIMARY KEY,

	room_id INTEGER NOT NULL,
	player_id INTEGER NOT NULL,

	challenge_selection TEXT NULL,

	player_number INTEGER NOT NULL,
	team INTEGER NULL,

	FOREIGN KEY(player_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(room_id) REFERENCES rooms(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE room_tracking (
	room_id INTEGER NOT NULL,
	k TEXT NOT NULL,
	v TEXT NOT NULL,

	FOREIGN KEY(room_id) REFERENCES rooms(id) ON DELETE CASCADE ON UPDATE CASCADE,
	PRIMARY KEY(room_id, k)
);

-- there must be at least 5 of each difficulty category in order to fill out the board
CREATE TABLE square_set_members (
	square_set_id INTEGER NOT NULL,
	square_id INTEGER NOT NULL,

	FOREIGN KEY(square_id) REFERENCES squares(id) ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(square_set_id) REFERENCES square_set_id(id) ON DELETE CASCADE ON UPDATE CASCADE,
	PRIMARY KEY(square_set_id, square_id)
);

CREATE TABLE room_feed (
	id SERIAL PRIMARY KEY,
	room_id INTEGER NOT NULL,

	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	in_game_time INTEGER NULL,
	actor INTEGER NOT NULL,
	type TEXT NOT NULL, -- joined, left, chatted, checked, unchecked, etc
	message TEXT NOT NULL,

	FOREIGN KEY(actor) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
	FOREIGN KEY(room_id) REFERENCES rooms(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE room_squares (
	room_id INTEGER NOT NULL,
	square_id INTEGER NOT NULL,

	position INTEGER NOT NULL,

	player_checked_state INTEGER NOT NULL DEFAULT 0, -- a bitmask

	FOREIGN KEY(room_id) REFERENCES rooms(id) ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(square_id) REFERENCES squares(id) ON DELETE RESTRICT ON UPDATE CASCADE,

	PRIMARY KEY(room_id, square_id)
);
