let initialize () =
  let register_all = List.iter Abca_models.Registry.register in

  List.iter register_all [
    Abca_plugin_life.Life.models;
    Abca_plugin_larger_than_life.Larger_than_life.models;
    Abca_plugin_cyclic.Cyclic.models;
    Abca_plugin_weighted_life.Weighted_life.models;
    Abca_plugin_generations.Generations.models;
  ]
  

