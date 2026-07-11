import type { PlanObject, UtilityNode } from '../domain/types';

// Real hookup topology — not the full adjacency-constraint matrix used for
// warnings, but exactly the physical cable/pipe runs a homesteader would
// actually wire up, so the plan can show *why* a battery room or pump sits
// where it does, not just leave the user to infer it from proximity alone.
function find(objects: PlanObject[], typeId: string): PlanObject | undefined {
  return objects.find((o) => o.typeId === typeId);
}

export function computeUtilityNodes(objects: PlanObject[]): UtilityNode[] {
  const nodes = new Map<string, UtilityNode>();
  const ensure = (obj: PlanObject, kind: 'power' | 'water'): UtilityNode => {
    let node = nodes.get(obj.id);
    if (!node) {
      node = { id: `util-${obj.id}`, objectId: obj.id, type: obj.typeId, kind, connections: [] };
      nodes.set(obj.id, node);
    }
    return node;
  };
  const link = (a: PlanObject, b: PlanObject, kind: 'power' | 'water') => {
    const na = ensure(a, kind);
    const nb = ensure(b, kind);
    if (!na.connections.includes(nb.id)) na.connections.push(nb.id);
  };

  // Power chain: any generation source feeds the battery room if present,
  // else straight into the inverter; battery and inverter link to each
  // other when both exist.
  const battery = find(objects, 'battery-room');
  const inverter = find(objects, 'inverter-room');
  const sink = battery ?? inverter;
  if (sink) {
    for (const typeId of ['solar-array', 'micro-hydro', 'generator']) {
      const source = find(objects, typeId);
      if (source && source.id !== sink.id) link(source, sink, 'power');
    }
  }
  if (battery && inverter) link(battery, inverter, 'power');

  // Water chain: well feeds the pump, which feeds a tank/cistern; a tank
  // with no pump (gravity- or rain-fed) links straight to the well.
  const well = find(objects, 'well');
  const pump = find(objects, 'pump');
  const tank = find(objects, 'water-tank') ?? find(objects, 'rainwater-cistern');
  if (well && pump) link(well, pump, 'water');
  if (pump && tank) link(pump, tank, 'water');
  else if (well && tank && !pump) link(well, tank, 'water');

  return [...nodes.values()];
}
