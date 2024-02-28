const mdcTextfield = require("@material/textfield");
const mdcRipple = require("@material/ripple");
const mdcDataTable = require("@material/data-table");
const smemory = require("share-memory-win");
const defaultSize = 32;
let grid = {};
let mouseDown = false;
let prevTile = null;
grid.size = parseInt(getValue("gridSize", 3, 3), 10) || defaultSize;
grid.tiles = [];
grid.arrows = [];
let sm = null;

class SharedMemWrap {
  /**
   * @param {String} name
   * @param {Integer} size in bytes (example: 32 means 32bytes)
   */
  constructor(size, name = "sharedMemForFluidSim", numOfElem = 3) {
    const os = require("os");
    this.le = os.endianness() == "LE";
    this.name = name;
    smemory.DeleteShareMemory(this.name);
    this.size = size;
    this.numOfElem = numOfElem;
    this.fullSize = (size + 2) * (size + 2) * this.numOfElem + 2;
    this.messageIdx = (size + 2) * (size + 2);
    this.buffer = Buffer.alloc(this.fullSize * 4);
    this.sm = smemory.CreateShareMemory(this.name, this.fullSize * 4);
    this.clear();
  }

  #loadToBuff() {
    smemory.ReadShareMemory(this.name, this.buffer);
  }

  #storeToMem() {
    smemory.WriteShareMemory(this.name, this.buffer);
  }

  clear() {
    this.buffer.fill(0);
    this.#storeToMem();
  }

  printBuf() {
    let buff = [];
    for (let index = 0; index < this.fullSize; index++) {
      this.le
        ? buff.push(this.buffer.readFloatLE(index * 4))
        : buff.push(this.buffer.readFloatBE(index * 4));
    }
    return buff;
  }

  read(index, elem, fast = false) {
    let calculated_idx = index * this.numOfElem + elem;
    if (calculated_idx >= this.fullSize)
      return console.log(
        `The what index! Max is ${this.fullSize}, asked idx was ${calculated_idx}`
      );
    if (!fast) this.#loadToBuff();
    return this.le
      ? this.buffer.readFloatLE(calculated_idx * 4)
      : this.buffer.readFloatBE(calculated_idx * 4);
  }
  write(index, elem, number, storeAfter = true) {
    let calculated_idx = index * this.numOfElem + elem;
    if (calculated_idx >= this.fullSize)
      return console.log(
        `The what index! Max ${this.fullSize}, idx was ${calculated_idx}`
      );
    this.le
      ? this.buffer.writeFloatLE(number, calculated_idx * 4)
      : this.buffer.writeFloatBE(number, calculated_idx * 4);
    if (storeAfter) this.#storeToMem();
  }
  read2d(col, row, elem, fast = false) {
    let calculated_idx = (col + row * (this.size + 2)) * this.numOfElem + elem;
    if (!fast) this.#loadToBuff();
    return this.le
      ? this.buffer.readFloatLE(calculated_idx * 4)
      : this.buffer.readFloatBE(calculated_idx * 4);
  }
  write2d(col, row, elem, number, storeAfter = true) {
    let calculated_idx = (col + row * (this.size + 2)) * this.numOfElem + elem;
    this.#loadToBuff();
    this.le
      ? this.buffer.writeFloatLE(number, calculated_idx * 4)
      : this.buffer.writeFloatBE(number, calculated_idx * 4);
    if (storeAfter) this.#storeToMem();
  }
  delete() {
    smemory.DeleteShareMemory(this.name);
    return null;
  }
}

var simulation_runs = (function () {
  let state = false;

  return {
    value: function () {
      return state;
    },
    toggle: function () {
      state = state ? false : true;
      return state;
    },
  };
})();
let dataTable = document.querySelector(".mdc-data-table");
if (dataTable) dataTable = new mdcDataTable.MDCDataTable(dataTable);

document.querySelector("#setupSim").addEventListener("click", () => {
  grid.size = parseInt(getValue("gridSize", 3, 3), 10);
  setGrid(grid.size);
});
document.querySelector("#simGrid").addEventListener("mouseenter", () => {
  mouseDown = false;
  prevTile = null;
});

document.querySelector("#startSim").addEventListener("click", () => {
  simulation_runs.toggle();
  if (simulation_runs.value()) {
    sm.write(sm.messageIdx, 0, 0.0);
    const child = require("child_process").execFile;
    document.querySelector("#setupSim").disabled = true;
    let args = [
      `-s=${grid.size}`,
      `-b=${getValue("blocks", 1, 1)}`,
      `-t=${getValue("threads", 1, 1)}`,
      `-d=${getValue("diffRate", 0.001, 0.0001)}`,
      `-w=${getValue("speed", 0.001, 0.0001)}`,
    ];
    //document.querySelector("#startSim").disabled = true;
    child(".\\fluid_sim_engine.exe", args, function (err, data) {
      if (err) return console.error(err);
      console.log(data.toString());
      let jsonData = JSON.parse(data.toString());
      document.querySelector("#framesT").innerHTML = jsonData?.frames || "--";
      document.querySelector("#difT").innerHTML =
        `${jsonData?.diffusion[1]}.${jsonData?.diffusion[2]} ms` || "-- ms";
      document.querySelector("#velT").innerHTML =
        `${jsonData?.velocity[1]}.${jsonData?.velocity[2]} ms` || "-- ms";
      console.log(jsonData);
    });
  } else {
    document.querySelector("#setupSim").disabled = false;
    if (sm) {
      sm.write(sm.messageIdx, 0, 1.0);
    }
  }

  switchStartButton();
});

document
  .querySelectorAll(".mdc-text-field")
  .forEach((textField) => new mdcTextfield.MDCTextField(textField));

document
  .querySelectorAll(".mdc-button")
  .forEach((button) => new mdcRipple.MDCRipple(button));

function setGrid(size, numbers = false) {
  size = size || defaultSize;
  let gridContainer = document.querySelector("#simGrid");
  gridContainer.innerHTML = "";
  document.documentElement.style.setProperty("--gridHeight", size);
  document.documentElement.style.setProperty("--gridWidth", size);
  grid.tiles = [];
  grid.arrows = [];
  for (let index = 0; index < size * size; index++) {
    let gridTile = document.createElement("div");
    gridTile.classList.add(["gridTile"]);
    gridTile.id = `tile${index}`;
    if (numbers) gridTile.innerHTML = index;
    gridTile.addEventListener("mouseenter", () => {
      draw(index);
    });
    gridTile.addEventListener("click", () => {
      draw(index, true);
    });
    gridTile.addEventListener("mousedown", () => {
      mouseDown = true;
      let row = parseInt(index / sm.size, 10);
      let col = index + 1 - sm.size * row;
      row += 1;
      prevTile = { x: col, y: row, when: Date.now() };
    });
    gridTile.addEventListener("mouseup", () => {
      mouseDown = false;
      prevTile = null;
    });
    gridContainer.appendChild(gridTile);
    grid.tiles.push(gridTile);
    let arrow = document.createElement("img");
    arrow.classList.add(["tileImage"]);
    arrow.src = "./img/arrow.png";
    gridTile.appendChild(arrow);
    grid.arrows.push(arrow);
  }
  if (sm) sm = sm.delete();
  sm = new SharedMemWrap(grid.size);
}

function getValue(id, defaultValue, min, max) {
  let value = document.querySelector(`#${id}`).value || defaultValue;
  return value < min ? defaultValue : value;
}

function switchStartButton() {
  let buttonText = document.querySelector("#startButtonText");
  buttonText.innerHTML = buttonText.innerHTML == "Start" ? "Stop" : "Start";
  buttonText.parentElement.classList.toggle("activeButton");
}
function updateGrid() {
  let startT = Date.now();
  let time = 0;
  if (!simulation_runs.value() && !mouseDown) time = 300;
  sm?.read(0, 0);
  let idx = 0;
  for (let row = 1; row <= sm?.size; row++)
    for (let col = 1; col <= sm?.size; col++) {
      grid.tiles[idx].style.backgroundColor = `hsl(250, 30%, ${
        sm?.read2d(col, row, 2, true) * 50
      }%)`;
      let u = sm?.read2d(col, row, 0, true);
      let v = sm?.read2d(col, row, 1, true);
      /*let u = 1;
      let v = 0;*/
      let mag = Math.sqrt(u * u + v * v);
      let scale = Math.max(0.1, Math.min(0.7, mag));
      let u_norm = u / mag;
      let v_norm = v / mag;
      let angle =
        (Math.atan2(u_norm, v_norm) - Math.atan2(1, 0)) * (180 / Math.PI);
      grid.arrows[idx].style.transform = `rotate(${-angle}deg) scale(${scale})`;
      idx++;
    }
  if (sm?.read(sm.messageIdx, 0, true) != 1.0) {
    sm?.write(sm.messageIdx, 0, 2.0);
  }
  let duration = Date.now() - startT;
  document.querySelector("#renderT").innerHTML = `${duration} ms`;
  return setTimeout(() => {
    updateGrid();
  }, time);
}

function draw(index, click = false) {
  if (!mouseDown && !click) return;
  let row = parseInt(index / sm.size, 10);
  let col = index + 1 - sm.size * row;
  row += 1;
  let diff = {};
  if (prevTile) {
    diff.x = col - prevTile.x;
    diff.y = row - prevTile.y;
    let mag = Math.sqrt(diff.x * diff.x + diff.y * diff.y);
    diff.x_n = diff.x / mag;
    diff.y_n = diff.y / mag;

    let speed = 30 / Math.max(Date.now() - prevTile.when, 0.1);
    sm?.write2d(col, row, 0, diff.x_n * speed);
    sm?.write2d(col, row, 1, diff.y_n * speed);
  }
  prevTile = { x: col, y: row, when: Date.now() };
  if (sm) sm.write2d(col, row, 2, 1.0);
}

setGrid(grid.size);
setGrid(grid.size);
updateGrid();
