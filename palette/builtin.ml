(*
 * ABCA (Agent-Based Cellular Automata)
 * A modular simulation framework for discrete spatial systems,
 * ranging from classical cellular automata to biologically inspired
 * agent-based models.
 *
 * Copyright (c) 2026 Edouard Evangelisti
 *
 * Distributed under the MIT License.
 * This software is provided "as is", without warranty of any kind.
 * See the LICENSE file for details.
 *)

let initialize () =
  Register.register Grayscale.generator;
  Register.register Heat.generator;
  Register.register Fire.generator;
  Register.register Cyclic.generator;
  Register.register Viridis.generator;
  Register.register Magma.generator;
  Register.register Plasma.generator;
  Register.register Inferno.generator;
  Register.register Cividis.generator
