// FIXME: it would be nice to be able to mark a box as impossible for a player too
document.addEventListener("DOMContentLoaded", function() {
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
	return baseColorTable[Math.floor(playerNumber % baseColorTable.length)] + Math.floor(playerNumber / baseColorTable.length) * 15;
}

function getColorForPlayerNumber(playerNumber) {
	if(window.currentPlayerTeam === playerNumber && personalColor !== null)
		return personalColor;

	var color = getColorForPlayerNumberHelper(playerNumber);
	if(window.currentPlayerTeam != -1 && personalColor !== null) {
		// too close for most colors, they'd be hard to differentiate
		if(Math.abs(color - personalColor) <= 15)
			return getColorForPlayerNumberHelper(window.currentPlayerTeam);
			// return 30; // this actually worked pretty well visually
		// and blue needs a wider range to be differentiated
		else if(color >= 225 && color <= 255 && personalColor >= 225 && personalColor <= 255)
			return getColorForPlayerNumberHelper(window.currentPlayerTeam);
			// return 30;
	}

	return color;
}

function setGradientForCheckedState(e, checkedState) {
	var g = gradientForCheckedState(checkedState);
	var before = e.style.background;
	e.style.background = g;
	// fallback if conic not supported
	if(g && e.style.background == before) {
		e.style.background = gradientForCheckedStateLinear(e.dataset.playerState|0);;
	}
}

function gradientForCheckedState(checkedState) {
	if(window.totalNumberOfTeams <= 2)
		return gradientForCheckedStateLinear(checkedState);
	else
		return gradientForCheckedStateConic(checkedState);
}

function gradientForCheckedStateConic(checkedState) {
	var playerMask = 1;

	var hits = 0;
	var colors = [];
	var stops = [];

	var allocation = 100 / window.totalNumberOfTeams;
	for(var i = 0; i < window.totalNumberOfTeams; i++) {

		var spot = i * allocation;

		if(checkedState & playerMask) {
			var color = getColorForPlayerNumber(i);
			stops.push("hsl("+color+", 100%, 25%) "+(spot)+"%");
			stops.push("hsl("+color+", 100%, 50%) "+(spot + allocation/2)+"%");
			stops.push("hsl("+color+", 100%, 25%) "+(spot + allocation)+"%");
			hits++;
		} else {
			stops.push("black "+(spot + 2)+"%");
			stops.push("black "+(spot + allocation - 2)+"%");
		}

		playerMask <<= 1;
	}

	if(hits == 0)
		return null;

	var s = "";

	s += "radial-gradient(circle, rgba(0, 0, 0, 0) 70%, rgba(0, 0, 0, 1) 75%), ";

	var slice = (360 / window.totalNumberOfTeams) / 2;
	var start = 360 - slice;
	if(window.currentPlayerTeam != -1)
		start -= window.currentPlayerTeam * slice * 2;

	s += "conic-gradient(from "+start+"deg, ";
	s += stops.join(", ");
	s += ")";

	return s;
}


function gradientForCheckedStateLinear(checkedState) {
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

	var s = "linear-gradient(135deg, ";
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

function getBingoSquares(header) {
	var label = header.textContent;

	var card = header;
	while(!card.classList.contains("bingo-card"))
		card = card.parentNode;

	var squares = card.querySelectorAll(".bingo-square");

	function helper(condition) {
		var answer = [];
		var x = 0, y = 0;
		for(var i = 0; i < squares.length; i++) {
			if(condition(x, y))
				answer.push(squares[i]);
			x += 1;
			if(x == 5) {
				x = 0;
				y += 1;
			}
		}
		return answer;
	}

	if(label == "TL-BR") {
		return helper(function(x, y) { return x == y; });
	} else if(label == "BL-TR") {
		return helper(function(x, y) { return (4-x) == y; });
	} else if(label.charAt(0) == "R") {
		return helper(function(x, y) { return y == label.charCodeAt(2) - 49; });
	} else /* must be a column */ {
		return helper(function(x, y) { return x == label.charCodeAt(2) - 49; });
	}
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
	if(location.search != "?restream") {
		setPersonalColor(pc);
	}

	document.querySelectorAll(".bingo-card th").forEach(function(e) {
		e.addEventListener("mouseenter", function(event) {
			getBingoSquares(event.target).forEach(function(s) {
				s.classList.add("hovering");
			});
		});

		e.addEventListener("mouseleave", function(event) {
			getBingoSquares(event.target).forEach(function(s) {
				s.classList.remove("hovering");
			});
		});
	});

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
		setGradientForCheckedState(e, e.dataset.playerState|0);
	});


	if(location.search != "?restream")
	try {
		var sp = sessionStorage.getItem("scrollPosition");
		if(sp) {
			sp = JSON.parse(sp);
			if(sp) {
				window.scrollTop = sp["x"];
				window.scrollLeft = sp["y"];
			}
		}
		sessionStorage.setItem("scrollPosition", null);

		var cc = sessionStorage.getItem("chatContent");
		if(cc) {
			cc = JSON.parse(cc);
			if(cc) {
				var ci = document.getElementById("chat-input");
				ci.value = cc.content;
				if(cc.focused)
					ci.focus();
			}
		}
		sessionStorage.setItem("chatContent", null);
	} catch(e) {
		console.log(e);
	}
});

var findTransparentRectanglesQueued = null;
function findTransparentRectanglesQueue() {
	if(findTransparentRectanglesQueued)
		return;
	findTransparentRectanglesQueued = setTimeout(findTransparentRectangles, 50);

}

function findTransparentRectangles() {
	findTransparentRectanglesQueued = null;

	document.querySelectorAll("span[data-property]").forEach(function(e) {
		setTimeout(function() { makeTextFit(e); }, 100);
	});

	var answers = [];
	var p = document.querySelector("#ffr-layout");
	document.querySelectorAll(".transparent, .transparent-itemset").forEach(function(e) {
		if(p != e.offsetParent)
			return;
		if(e.offsetWidth == 0 || e.offsetHeight == 0)
			return;

		var rect = {};
		rect.left = e.offsetLeft;
		rect.top = e.offsetTop;
		rect.width = e.offsetWidth;
		rect.height = e.offsetHeight;

		answers.push(rect);
	});

	// want to get the image out of the stylesheet
	p.style.backgroundImage = null;
	var cs = getComputedStyle(p);
	var bgimg = cs.backgroundImage;
	if(bgimg == "none")
		return;

	var img = new Image();
	img.src = bgimg.substring(5, bgimg.length - 2);
	img.onload = function() {
		var canvas = document.createElement("canvas");
		canvas.setAttribute("width", 1280);
		canvas.setAttribute("height", 720);
		var ctx = canvas.getContext("2d");
		ctx.drawImage(img, 0, 0);

		var idata = ctx.getImageData(0, 0, canvas.width, canvas.height);
		var data = idata.data;

		for(var rect of answers) {
			for(var y = rect.top; y < rect.top + rect.height; y++)
			for(var x = rect.left; x < rect.left + rect.width; x++) {
				var i = y * canvas.width + x;
				i *= 4;
				data[i + 0] = 0;
				data[i + 1] = 0;
				data[i + 2] = 0;
				data[i + 3] = 0;
			}
		}

		ctx.putImageData(idata, 0, 0);

		p.style.backgroundImage = "url('" + canvas.toDataURL() + "')";
	};

	return answers;
}

// see above for where this s is called this on all possible elements when the theme changes
function makeTextFit(element) {

	element.style.transform = null;
	element.style.transformOrigin = null;
	element.style.display = null;
	element.classList.remove("shrunk");
	element.parentNode.classList.remove("contains-shrunk");

	if(element.parentNode.classList.contains("squeeze-vertically")) {
		var cs = getComputedStyle(element.parentNode);

		var maxSize = element.parentNode.offsetHeight -
			parseFloat(cs.borderTopWidth) -
			parseFloat(cs.paddingTop) -
			parseFloat(cs.borderBottomWidth) -
			parseFloat(cs.paddingBottom);

		var currentSize = element.offsetHeight;

		if(maxSize <= 0)
			return;

		if(currentSize <= 0)
			return;

		if(currentSize > maxSize) {
			var ratio = maxSize / currentSize;
			element.style.transform = "scaleY("+ratio+")";
			element.style.transformOrigin = "left top";
			element.style.display = "block";
			element.classList.add("shrunk");
			element.parentNode.classList.add("contains-shrunk");
		}
	} else {
		var cs = getComputedStyle(element.parentNode);

		var maxSize = element.parentNode.offsetWidth -
			parseFloat(cs.borderLeftWidth) -
			parseFloat(cs.paddingLeft) -
			parseFloat(cs.borderRightWidth) -
			parseFloat(cs.paddingRight);

		var currentSize = element.offsetWidth;

		if(maxSize <= 0)
			return;

		if(currentSize <= 0)
			return;

		if(currentSize > maxSize) {
			var ratio = maxSize / currentSize;
			element.style.transform = "scaleX("+ratio+")";
			element.style.transformOrigin = "left center";
			element.style.display = "block";
			element.classList.add("shrunk");
			element.parentNode.classList.add("contains-shrunk");
		}
	}
}

var detailsTimeout;
var autoRotateDetails = false;

function queueNextDetailsPage(currentPage) {
	if(autoRotateDetails) {
		if(!detailsTimeout) {
			var pages = document.querySelectorAll(".info-area > div > span");

			var pageIndex = currentPage - 1;

			var max = pages.length;
			while(max > 0) {
				max--;
				pageIndex++;
				if(pageIndex >= pages.length)
					pageIndex = 0;

				if(pages[pageIndex].textContent != "")
					break;
			}

			if(pageIndex < 0)
				return;

			if(pages[pageIndex].textContent != "")
				detailsTimeout = setTimeout(function() {
					fadeInDetails(pageIndex + 1);
				}, 30000);
		}
	}

}

function fadeInDetails(page) {
	var pages = document.querySelectorAll(".info-area > div");
	if(pages.length == 0)
		return;

	if(detailsTimeout) {
		clearTimeout(detailsTimeout);
		detailsTimeout = null;
	}

	var container = pages[0].parentNode;
	if(container.classList.contains("actively-showing")) {
		container.classList.remove("actively-showing");
		if(page)
			detailsTimeout = setTimeout(function() { fadeInDetails(page); }, 500);
		return;
	}

	if(page) {
		container.classList.add("actively-showing");

		// max show time = 15 seconds
		detailsTimeout = setTimeout(function() {
			fadeInDetails(0);
			queueNextDetailsPage(page);
		}, 15000);

		pages.forEach(function(p) {
			p.style.display = "none";
		});

		pages[page-1].style.display = "block";

		setTimeout(function() {
			makeTextFit(pages[page-1].querySelector("span"));
		}, 50);
	}
}

function cacheBuster() {
	return "?9";
}

function updateTrackerProperty(key, value) {

	document.querySelectorAll("[name=\"" + key + "\"]").forEach(function(e) {
		if(e.type == "checkbox")
			e.checked = value == "on";
		else
			e.value = value;
	});

	switch(key) {
		case "incentives-json":
			try {
				receiveIncentivesUpdate(value);
			} catch(e) {
				console.log(e);
			}
		break;
		case "showing-details-page":
			fadeInDetails(value|0);
		break;
		case "auto-rotate-details":
			autoRotateDetails = value == "on";
			if(autoRotateDetails)
				setTimeout(function() { queueNextDetailsPage(0); }, 1000);
		break;
		case "clock":
			trackerClockTicks = value|0;
			updateTrackerClock();
			return;
		case "clock-running":
			if(value == "on")
				startTrackerClock();
			else
				stopTrackerClock();
			break;
		case "layout-sheet":
			var i = document.getElementById("layout-stylesheet");
			if(i) {
				i.href = "/assets/tracker/layouts/" + value + cacheBuster();
				findTransparentRectanglesQueue();
			}
			return;
		case "style-sheet":
			var i = document.getElementById("theme-stylesheet");
			if(i) {
				i.href = "/assets/tracker/themes/" + value + cacheBuster();
				findTransparentRectanglesQueue();
			}
			return;
		case "logo-sheet":
			var i = document.getElementById("logo-stylesheet");
			if(i) {
				i.href = "/assets/tracker/logos/" + value + cacheBuster();
			}
			return;
		case "show-rank-boxes":
		case "show-cameras":
		case "player-4-showing":
			var m = document.querySelector("#ffr-layout");
			if(m) {
				if(value == "on")
					m.classList.add(key);
				else
					m.classList.remove(key);
				findTransparentRectanglesQueue();
			}

			break;
		default:
			// handled below
			break;
	}

	if(key.startsWith("item-player-")) {
		var prefix = key.substring(0, "item-player-X-".length);
		var item = key.substring("item-player-X-".length);

		document.querySelectorAll("[data-property-prefix=\""+prefix+"\"] ." + item).forEach(function(e) {
			e.classList.remove("on");
			e.classList.remove("tri-on");
			e.classList.remove("quad-on");
			e.classList.remove("penta-on");

			e.classList.forEach(function(o) {
				if(o.startsWith("option-"))
					e.classList.remove(o);
			});

			if(value.length)
				e.classList.add(value);
		});

		return;
	}

	document.querySelectorAll("[data-property=\"" + key + "\"]").forEach(function(e) {
		if(e.classList.contains("tracker")) {
			for(c of e.classList) {
				if(c.indexOf("-itemset") != -1) {
					if(c == "transparent-itemset")
						findTransparentRectanglesQueue();
					e.classList.remove(c);
				}
			}

			if(value == "transparent-itemset")
				findTransparentRectanglesQueue();

			e.classList.add(value);
		} else if(e.classList.contains("wins-counter")) {
			e.innerHTML = "";
			var parts = value.split("/");
			if(parts.length == 2) {
				var wins = Number(parts[0]);
				var needed = Math.floor(Number(parts[1]) / 2 + 1);

				for(var thing = 0; thing < needed; thing++) {
					var thingElement = document.createElement("span");
					thingElement.className = "win-indicator";
					if(thing < wins)
						thingElement.className += " indicated-win";
					e.appendChild(thingElement);
				}
			}
		} else if(e.tagName == "SPAN") {
			e.textContent = value;
			setTimeout(function() { makeTextFit(e); }, 100); // idk why this needs a timer but it does seem to help soooo maybe the value isn't recalculated right until it gets painted?
		} else if(e.tagName == "DIV") {
			if(e.classList.contains("class-toggle")) {
				e.classList.toggle(value);
			} else if(e.classList.contains("color")) {
				e.classList.remove("player-0-checked");
				e.classList.remove("player-1-checked");
				e.classList.remove("player-2-checked");
				e.classList.remove("player-3-checked");
				e.classList.remove("transparent");

				if(value == "A")
					e.classList.add("player-0-checked");
				else if(value == "B")
					e.classList.add("player-1-checked");
				else if(value == "C")
					e.classList.add("player-2-checked");
				else if(value == "D")
					e.classList.add("player-3-checked");
				else
					e.classList.add("transparent");
			} else {
				if(value == "on")
					e.classList.add("property-enabled");
				else
					e.classList.remove("property-enabled");
				e.style.display = value == "on" ? "block" : "none";
			}
		}
	});
}

function clockInfo(clockTicks) {
	var totalSeconds = clockTicks / 1000;

	var string;
	var seconds;

	if(totalSeconds >= 0) {
		var hours = Math.floor(totalSeconds / 3600);
		var minutes = Math.floor((totalSeconds - (hours * 3600)) / 60);
		seconds = Math.floor((totalSeconds|0) % 60);

		string = hours + ":" + (minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
	} else {
		seconds = Math.floor(totalSeconds + .5);
		string = "-0:00:" + (seconds > -10 ? '0' : '') + -seconds;
	}

	return {"string": string, "seconds": seconds};
}

function clockStringToTicks(clockString) {
	var negative = false;
	if(clockString.charAt(0) == "-") {
		negative = true;
		clockString = clockString.substring(1);
	}
	var parts = clockString.split(":");
	var hours = 0;
	var minutes = 0;
	var seconds = 0;
	if(parts.length == 3) {
		hours = parts[0]|0;
		minutes = parts[1]|0;
		seconds = parts[2]|0;
	} else if(parts.length == 2) {
		minutes = parts[0]|0;
		seconds = parts[1]|0;
	} else if(parts.length == 1) {
		seconds = parts[0]|0;
	}

	return (hours * 3600 + minutes * 60 + seconds) * (negative ? -1000 : 1000);
}

var trackerClockTicks = 0;

function updateTrackerClock() {
	var c = clockInfo(trackerClockTicks).string;

	document.querySelectorAll(".active-clock, [name=clock]").forEach(function(e) {
		if(e.tagName == "SPAN")
			e.textContent = c;
		else
			e.value = c;
	});
}

var trackerClockTimeout;
var previousIntervalDate;

function startTrackerClock() {
	previousIntervalDate = new Date();
	trackerClockTimeout = setInterval(function() {
		var n = new Date();
		trackerClockTicks += n - previousIntervalDate;
		previousIntervalDate = n;
		updateTrackerClock();
	}, 1000);
}

function stopTrackerClock() {
	clearInterval(trackerClockTimeout);
	trackerClockTimeout = null;
}

function openEventSource() {

	var c = location.href;
	var url = "event-stream";

	// bypass the annoying 6 connection limit via random subdomain
	if(c.indexOf("//adamdruppe.com" != 0)) {
		url = c.substring(0, c.lastIndexOf("/") + 1).
			replace("adamdruppe.com", "stream"+Math.floor(Math.random() * 100)+".adamdruppe.com") + url;
		console.log("Connecting to " + url);
	}

	var source = new EventSource(url);

	return source;
}

function activateTracking(data, reloadPage) {

	// initial population, data comes from the server side template
	for(key in data) {
		var value = data[key];
		try {
			updateTrackerProperty(key, value);
		} catch(e) {
			console.error(e);
		}
	}

	var source = openEventSource();

	var sourceTimeout;
	function keepalive(period) {
		if(!period)
			period = 18000;
		if(sourceTimeout)
			clearTimeout(sourceTimeout);
		sourceTimeout = setTimeout(reloadPage, period);
	}

	keepalive();

	source.addEventListener("keepalive", function() { keepalive(); });

	source.addEventListener("tracker_update", function(event) {
		var obj = JSON.parse(event.data);

		try {
			updateTrackerProperty(obj.key, obj.value);
		} catch(e) {
			console.error(e);
		}

		keepalive();
	});
}


// FIXME: the tracker page needs to listen to updates too
// FIXME: make final time stand out
// FIXME: see about combining the bingo for more event source integration, easy to run out rn.
