module Convex exposing (main)

{- For a useful benchmark,
   copy and rename an older baseline version of Physics/Convex.elm
   to Physics/OriginalConvex.elm and uncomment the import below,
   then toggle the usage in benchmarks.

   Switching it back to use the (current) Convex.elm through the
   OriginalConvex alias keeps obsolete or redundant code out of
   the repo while the comparison benchmarks continue to be maintained and
   built and run essentially as absolute non-comparison benchmarks until
   they are needed again in another round of performance work.
-}
{- import Physics.OriginalConvex as OriginalConvex -}

import Benchmark exposing (..)
import Benchmark.Runner exposing (BenchmarkProgram, program)
import Internal.Convex as Convex
import Internal.Quaternion as Quaternion
import Internal.Vector3 as Vec3 exposing (Vec3, vec3)


main : BenchmarkProgram
main =
    program suite


suite : Benchmark
suite =
    let
        sampleHull =
            vec3 1 1 1
                |> Convex.fromBox

        originalSampleHull =
            vec3 1 1 1
                |> {- OriginalConvex.fromBox -} Convex.fromBox

        trivialVisitor : Vec3 -> Vec3 -> Int -> Int
        trivialVisitor _ _ _ =
            0

        sepNormal =
            vec3 0 0 1

        -- Move the box 0.45 units up
        -- only 0.05 units of the box will be below plane z=0
        transform =
            { position = vec3 0 0 0.45
            , orientation = Quaternion.identity
            }

        -- points in the plane z
        worldVertsB =
            [ vec3 -1.0 -1.0 0
            , vec3 -1.0 1.0 0
            , vec3 1.0 1.0 0
            , vec3 1.0 -1.0 0
            ]

        boxHull halfExtent =
            Convex.fromBox
                (vec3 halfExtent halfExtent halfExtent)

        originalBoxHull halfExtent =
            {- OriginalConvex.fromBox -}
            Convex.fromBox
                (vec3 halfExtent halfExtent halfExtent)
    in
    describe "Convex"
        [ Benchmark.compare "foldFaceNormals"
            "baseline"
            (\_ ->
                {- OriginalConvex.foldFaceNormals -}
                Convex.foldFaceNormals
                    -- fold a function with minimal overhead
                    trivialVisitor
                    0
                    originalSampleHull
            )
            "latest code"
            (\_ ->
                Convex.foldFaceNormals
                    -- fold a function with minimal overhead
                    trivialVisitor
                    0
                    sampleHull
            )

        -- We will now clip a face in hullA that is closest to the
        -- sepNormal against the points in worldVertsB.
        -- We can expect to get back the 4 corners of the box hullA
        -- penetrated 0.05 units into the plane worldVertsB we
        -- constructed.
        , Benchmark.compare "clipFaceAgainstHull"
            "baseline"
            (\_ ->
                {- OriginalConvex.clipFaceAgainstHull -}
                Convex.clipFaceAgainstHull
                    transform
                    (originalBoxHull 0.5)
                    sepNormal
                    worldVertsB
            )
            "latest code"
            (\_ ->
                Convex.clipFaceAgainstHull
                    transform
                    (boxHull 0.5)
                    sepNormal
                    worldVertsB
            )
        ]
