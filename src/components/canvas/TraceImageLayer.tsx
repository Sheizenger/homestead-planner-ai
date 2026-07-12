import type { TraceImage } from '../../state/projectStore';

// A positionable, scalable backdrop image (e.g. a satellite/map screenshot)
// rendered behind everything else on the interactive canvas so the plot
// boundary can be traced over it with the existing polygon vertex editor.
// Session-only — never rendered by StaticPlanRender, so it never leaks into
// exports.
export function TraceImageLayer({ image }: { image: TraceImage | null }) {
  if (!image) return null;
  const heightM = image.widthM * (image.naturalHeightPx / image.naturalWidthPx);
  return (
    <image
      href={image.dataUrl}
      x={image.xM}
      y={image.yM}
      width={image.widthM}
      height={heightM}
      opacity={image.opacity}
      preserveAspectRatio="none"
      className="pointer-events-none"
    />
  );
}
