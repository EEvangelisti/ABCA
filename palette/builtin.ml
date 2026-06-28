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
