// FIXME: it would be nice to be able to mark a box as impossible for a player too

document.querySelectorAll("form.background-submit").forEach(function(e) {
	e.querySelectorAll("button[name]").forEach(function(button) {
		button.addEventListener("click", function() {
			e.buttonClicked = button;
		});
	});


	e.addEventListener("submit", function(event) {
		var req = new XMLHttpRequest();
		req.open("POST", event.target.action);
		var fd = new FormData(event.target);
		if(event.target.buttonClicked) {
			var button = event.target.buttonClicked;
			fd.append(button.name, button.value);
		}
		req.send(fd);
		event.preventDefault();
		if(!event.target.classList.contains("no-reset"))
			event.target.reset();
	});
});

// put the green ones last trying to be most rg blind friendly.....
var baseColorTable = [
	0, // red
	180, // cyan
	240, // blue
	300, // purple
	60, // yellow
	120 // green
];

function getColorForPlayerNumberHelper(playerNumber) {
	return baseColorTable[Math.floor(playerNumber % 6)] + Math.floor(playerNumber / 6) * 15;
}

function getColorForPlayerNumber(playerNumber) {
	if(window.currentPlayerNumber === playerNumber && personalColor !== null)
		return personalColor;

	var color = getColorForPlayerNumberHelper(playerNumber);
	if(window.currentPlayerNumber != -1 && personalColor !== null) {
		// too close for most colors, they'd be hard to differentiate
		if(Math.abs(color - personalColor) <= 15)
			return getColorForPlayerNumberHelper(window.currentPlayerNumber);
			// return 30; // this actually worked pretty well visually
		// and blue needs a wider range to be differentiated
		else if(color >= 225 && color <= 255 && personalColor >= 225 && personalColor <= 255)
			return getColorForPlayerNumberHelper(window.currentPlayerNumber);
			// return 30;
	}

	return color;
}

function gradientForCheckedState(checkedState) {
	var playerMask = 1;

	var hits = 0;
	var colors = [];

	for(var i = 0; i < 30; i++) {
		if(checkedState & playerMask) {
			hits++;

			colors.push(i);
		}

		playerMask <<= 1;
	}

	if(hits == 0)
		return null;

	var stops = [];

	if(hits == 1) {
		var color = getColorForPlayerNumber(colors[0]);

		stops.push("hsl("+color+", 100%, 50%) 0%");
		stops.push("hsl("+color+", 100%, 25%) 50%");
		stops.push("hsl("+color+", 100%, 50%) 100%");

		/*
		#f00 0%,
		#a00 48%,
		#077 52%,
		#0ff 100%);
		*/
	} else for(var i = 0; i < colors.length; i++) {
		var color = getColorForPlayerNumber(colors[i]);

		var allocation = 100 / hits;
		var spot = i * allocation;

		if(i % 2 == 0) {
			stops.push("hsl("+color+", 100%, 50%) "+(spot + 2)+"%");
			stops.push("hsl("+color+", 100%, 25%) "+(spot + allocation - 2)+"%");
		} else {
			stops.push("hsl("+color+", 100%, 25%) "+(spot + 2)+"%");
			stops.push("hsl("+color+", 100%, 50%) "+(spot + allocation - 2)+"%");
		}
	}

	var s = "linear-gradient(45deg, ";
	s += stops.join(", ");
	s += ")";

	return s;
}

var personalColor;

function newPersonalColor(color) {
	window.localStorage.setItem("personalColor", color);

	setPersonalColor(color);
}

function setPersonalColor(color) {
	document.querySelector(":root").style.setProperty("--personal-color", color);
	personalColor = color|0;
}

var clockSoundsEnabled = false;
var chatSoundsEnabled = false;

document.addEventListener("DOMContentLoaded", function() {
	var test = window.localStorage.getItem("clockSoundsEnabled");
	if(test === "true")
		clockSoundsEnabled = true;
	test = window.localStorage.getItem("chatSoundsEnabled");
	if(test === "true")
		chatSoundsEnabled = true;

	var pc = window.localStorage.getItem("personalColor");
	if(!pc)
		pc = 0;
	var picker = document.getElementById("personal-color-picker");
	if(picker)
		picker.value = pc;
	setPersonalColor(pc);

	picker = document.getElementById("clock-sound-picker");
	if(picker) {
		picker.checked = clockSoundsEnabled;
		picker.onchange = function(event) {
			window.localStorage.setItem("clockSoundsEnabled", event.target.checked ? "true" : "false");
		};
	}
	picker = document.getElementById("chat-sound-picker");
	if(picker) {
		picker.checked = chatSoundsEnabled;
		picker.onchange = function(event) {
			window.localStorage.setItem("chatSoundsEnabled", event.target.checked ? "true" : "false");
		};
	}

	document.querySelectorAll("[data-player-state]").forEach(function(e) {
		e.style.background = gradientForCheckedState(e.dataset.playerState|0);
	});

	try {
		var sp = sessionStorage.getItem("scrollPosition");
		if(sp) {
			sp = JSON.parse(sp);
			if(sp) {
				window.scrollTop = sp["x"];
				window.scrollLeft=  sp["y"];
			}
		}
		sessionStorage.setItem("scrollPosition", null);
	} catch(e) {
		console.log(e);
	}
});
