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
  let register_all = List.iter Abca_models.Registry.register in

  List.iter register_all [
    Abca_plugin_life.Life.models;
    Abca_plugin_larger_than_life.Larger_than_life.models;
    Abca_plugin_cyclic.Cyclic.models;
    Abca_plugin_weighted_life.Weighted_life.models;
    Abca_plugin_generations.Generations.models;
    Abca_plugin_zoospores.Zoospores.models;
    Abca_plugin_hyphae.Hyphae.models;
  ]
  

