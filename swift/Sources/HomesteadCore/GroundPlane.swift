//
//  GroundPlane.swift
//  HomesteadCore
//
//  Where a flat polygon lands once it has been laid down.
//
//  A mesh is placed directly: the plan says an object is at (x, y) and the
//  node goes to (x, elevation, y). A slab cannot be, because the only way to
//  build an arbitrary polygon in SceneKit is to draw it as a 2D path and
//  extrude it — and a path is drawn standing up, in the XY plane, so it has
//  to be rotated down into the ground before it means anything.
//
//  That rotation is a quarter turn about X, and a quarter turn about X sends
//  the path's y to the scene's *minus* z. Laid down, a slab drawn straight
//  from plan coordinates therefore lands on the far side of the origin from
//  every mesh — the whole plot's depth away from the buildings standing on
//  it. It did exactly that, and the ground was drawn beside the homestead
//  rather than under it.
//
//  So the mapping lives here rather than in the view, where nothing on Linux
//  can reach it: this file is three arithmetic functions and the tests beside
//  it are the ones that would have caught it.
//

import HomesteadEngine

public enum GroundPlane {
    /// The quarter turn that lays a standing path down into the ground.
    public static let pitch = -Double.pi / 2

    /// Where a plan point goes in the path, before the turn.
    ///
    /// Mirrored, because the turn mirrors it back.
    public static func pathPoint(_ point: Point) -> Point {
        Point(x: point.x, y: -point.y)
    }

    /// The path a slab's polygon is drawn as.
    ///
    /// Reversed, because mirroring a polygon reverses which way round it is
    /// drawn, and which way round it is drawn is what decides which way its
    /// faces point. Mirrored and reversed, it winds the way it started.
    public static func path(_ polygon: [Point]) -> [Point] {
        polygon.reversed().map(pathPoint)
    }

    /// Where a point of that path ends up once the turn is applied.
    ///
    /// The quarter turn about X: `y' = y·cos − z·sin`, `z' = y·sin + z·cos`
    /// at `sin = -1`, `cos = 0`, for a path that is flat so `z` is zero.
    public static func laidDown(_ point: Point) -> Vector3 {
        Vector3(x: point.x, y: 0, z: -point.y)
    }

    /// The thickness a slab is actually extruded by.
    ///
    /// A slab with no thickness still has to be a solid, or there is nothing
    /// to extrude and nothing to draw.
    public static func extrusion(_ thickness: Double) -> Double {
        max(0.01, thickness)
    }

    /// Where the node's centre goes so that the top face lands on `top`.
    ///
    /// `SCNShape` extrudes a path centred on its own zero: half the thickness
    /// in front of the path and half behind. A node placed at `top`
    /// therefore puts half the slab *above* the height it was meant to reach.
    /// The ground is 1.6m thick, so its surface stood 0.8m proud of the plane
    /// every mesh is placed on, and the whole homestead was buried to the
    /// knee in its own lawn.
    public static func centre(top: Double, thickness: Double) -> Double {
        top - extrusion(thickness) / 2
    }

    /// Where a plan point ends up in the scene: the whole trip.
    ///
    /// This must agree with where a mesh at the same plan point is placed,
    /// or the ground is not under the buildings.
    public static func scenePoint(_ point: Point) -> Vector3 {
        laidDown(pathPoint(point))
    }
}
