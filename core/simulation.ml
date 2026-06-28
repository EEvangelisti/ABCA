type ('state, 'params) t = {
  model  : string;
  engine : ('state, 'params) Engine.t;
}

let create ~model ~grid ~rule ~params ?(keep_history = true) () =
  {
    model;
    engine =
      Engine.create
        ~grid
        ~rule
        ~params
        ~keep_history
        ();
  }

let model sim = sim.model
let engine sim = sim.engine
let grid sim = Engine.grid sim.engine
let generation sim = Engine.generation sim.engine
let current sim = Engine.current sim.engine
let history sim = Engine.history sim.engine

let step sim =
  { sim with engine = Engine.step sim.engine }

let run n sim =
  { sim with engine = Engine.run n sim.engine }
