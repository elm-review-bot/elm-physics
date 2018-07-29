module Physics.NarrowPhase exposing (getContacts)

import Array.Hamt as Array exposing (Array)
import Dict exposing (Dict)
import Math.Vector3 as Vec3 exposing (Vec3)
import Physics.Body as Body exposing (Body, BodyId)
import Physics.Const as Const
import Physics.ContactEquation as ContactEquation exposing (ContactEquation)
import Physics.ConvexPolyhedron as ConvexPolyhedron exposing (ConvexPolyhedron, Face)
import Physics.Quaternion as Quaternion
import Physics.Shape as Shape exposing (Shape(..))
import Physics.Transform as Transform exposing (Transform)
import Physics.World as World exposing (World)
import Set exposing (Set)


getContacts : World -> List ContactEquation
getContacts world =
    Set.foldl
        (\( bodyId1, bodyId2 ) ->
            Maybe.map2
                (getBodyContacts world bodyId1 bodyId2)
                (Dict.get bodyId1 world.bodies)
                (Dict.get bodyId2 world.bodies)
                |> Maybe.withDefault identity
        )
        []
        (World.getPairs world)


getBodyContacts : World -> BodyId -> BodyId -> Body -> Body -> List ContactEquation -> List ContactEquation
getBodyContacts world bodyId1 bodyId2 body1 body2 contactEquations =
    Dict.foldl
        (\shapeId1 shape1 currentContactEquations1 ->
            Dict.foldl
                (\shapeId2 shape2 currentContactEquations2 ->
                    getShapeContacts
                        (Body.shapeWorldTransform shapeId1 body1)
                        shape1
                        bodyId1
                        body1
                        (Body.shapeWorldTransform shapeId2 body2)
                        shape2
                        bodyId2
                        body2
                        currentContactEquations2
                )
                currentContactEquations1
                body2.shapes
        )
        contactEquations
        body1.shapes


getShapeContacts : Transform -> Shape -> BodyId -> Body -> Transform -> Shape -> BodyId -> Body -> List ContactEquation -> List ContactEquation
getShapeContacts shapeTransform1 shape1 bodyId1 body1 shapeTransform2 shape2 bodyId2 body2 contactEquations =
    case ( shape1, shape2 ) of
        ( Plane, Plane ) ->
            -- don't collide two planes
            contactEquations

        ( Plane, Convex convexPolyhedron ) ->
            addPlaneConvexContacts
                shapeTransform1
                bodyId1
                body1
                shapeTransform2
                convexPolyhedron
                bodyId2
                body2
                contactEquations

        ( Plane, Sphere radius ) ->
            addPlaneSphereContacts
                shapeTransform1
                bodyId1
                body1
                shapeTransform2
                radius
                bodyId2
                body2
                contactEquations

        ( Convex convexPolyhedron, Plane ) ->
            addPlaneConvexContacts
                shapeTransform2
                bodyId2
                body2
                shapeTransform1
                convexPolyhedron
                bodyId1
                body1
                contactEquations

        ( Convex convexPolyhedron1, Convex convexPolyhedron2 ) ->
            addConvexConvexContacts
                shapeTransform1
                convexPolyhedron1
                bodyId1
                body1
                shapeTransform2
                convexPolyhedron2
                bodyId2
                body2
                contactEquations

        ( Convex convexPolyhedron, Sphere radius ) ->
            addSphereConvexContacts
                shapeTransform2
                radius
                bodyId2
                body2
                shapeTransform1
                convexPolyhedron
                bodyId1
                body1
                contactEquations

        ( Sphere radius, Plane ) ->
            addPlaneSphereContacts
                shapeTransform1
                bodyId1
                body1
                shapeTransform2
                radius
                bodyId2
                body2
                contactEquations

        ( Sphere radius, Convex convexPolyhedron ) ->
            addSphereConvexContacts
                shapeTransform1
                radius
                bodyId1
                body1
                shapeTransform2
                convexPolyhedron
                bodyId2
                body2
                contactEquations

        ( Sphere radius1, Sphere radius2 ) ->
            addSphereSphereContacts
                shapeTransform1
                radius1
                bodyId1
                body1
                shapeTransform2
                radius2
                bodyId2
                body2
                contactEquations


addPlaneConvexContacts : Transform -> BodyId -> Body -> Transform -> ConvexPolyhedron -> BodyId -> Body -> List ContactEquation -> List ContactEquation
addPlaneConvexContacts planeTransform planeBodyId planeBody convexTransform convexPolyhedron convexBodyId convexBody contactEquations =
    let
        worldNormal =
            Quaternion.rotate planeTransform.quaternion Vec3.k
    in
        Array.foldl
            (\vertex currentContactEquations ->
                let
                    worldVertex =
                        Transform.pointToWorldFrame convexTransform vertex

                    dot =
                        planeTransform.position
                            |> Vec3.sub worldVertex
                            |> Vec3.dot worldNormal
                in
                    if dot <= 0 then
                        { bodyId1 = planeBodyId
                        , bodyId2 = convexBodyId
                        , ni = worldNormal
                        , ri =
                            Vec3.sub
                                (worldNormal
                                    |> Vec3.scale dot
                                    |> Vec3.sub worldVertex
                                )
                                planeBody.position
                        , rj = Vec3.sub worldVertex convexBody.position
                        , restitution = 0
                        }
                            :: currentContactEquations
                    else
                        currentContactEquations
            )
            contactEquations
            convexPolyhedron.vertices


addConvexConvexContacts : Transform -> ConvexPolyhedron -> BodyId -> Body -> Transform -> ConvexPolyhedron -> BodyId -> Body -> List ContactEquation -> List ContactEquation
addConvexConvexContacts shapeTransform1 convexPolyhedron1 bodyId1 body1 shapeTransform2 convexPolyhedron2 bodyId2 body2 contactEquations =
    case ConvexPolyhedron.findSeparatingAxis shapeTransform1 convexPolyhedron1 shapeTransform2 convexPolyhedron2 of
        Just sepAxis ->
            ConvexPolyhedron.clipAgainstHull shapeTransform1 convexPolyhedron1 shapeTransform2 convexPolyhedron2 sepAxis -100 100
                |> List.foldl
                    (\{ point, normal, depth } currentContactEquations ->
                        let
                            q =
                                normal
                                    |> Vec3.negate
                                    |> Vec3.scale depth

                            ri =
                                Vec3.add point q
                                    |> Vec3.add (Vec3.negate body1.position)

                            rj =
                                point
                                    |> Vec3.add (Vec3.negate body2.position)
                        in
                            { bodyId1 = bodyId1
                            , bodyId2 = bodyId2
                            , ni = Vec3.negate sepAxis
                            , ri = ri
                            , rj = rj
                            , restitution = 0
                            }
                                :: currentContactEquations
                    )
                    contactEquations

        Nothing ->
            contactEquations


addPlaneSphereContacts : Transform -> BodyId -> Body -> Transform -> Float -> BodyId -> Body -> List ContactEquation -> List ContactEquation
addPlaneSphereContacts planeTransform bodyId1 body1 t2 radius bodyId2 body2 contactEquations =
    let
        worldPlaneNormal =
            Quaternion.rotate planeTransform.quaternion Vec3.k

        worldVertex =
            worldPlaneNormal
                |> Vec3.scale radius
                |> Vec3.sub t2.position

        dot =
            planeTransform.position
                |> Vec3.sub worldVertex
                |> Vec3.dot worldPlaneNormal
    in
        if dot <= 0 then
            { bodyId1 = bodyId1
            , bodyId2 = bodyId2
            , ni = worldPlaneNormal
            , ri =
                Vec3.sub
                    (worldPlaneNormal
                        |> Vec3.scale dot
                        |> Vec3.sub worldVertex
                    )
                    body1.position
            , rj = Vec3.sub worldVertex body2.position
            , restitution = 0
            }
                :: contactEquations
        else
            contactEquations


addSphereConvexContacts : Transform -> Float -> BodyId -> Body -> Transform -> ConvexPolyhedron -> BodyId -> Body -> List ContactEquation -> List ContactEquation
addSphereConvexContacts t1 radius bodyId1 body1 t2 { vertices, faces } bodyId2 body2 contactEquations =
    -- Check corners
    vertices
        |> Array.foldl
            (\vertex ( prevContact, maxPenetration ) ->
                let
                    -- World position of corner
                    worldCorner =
                        Transform.pointToWorldFrame t2 vertex

                    penetration =
                        radius - Vec3.distance worldCorner t1.position
                in
                    if penetration >= maxPenetration then
                        ( Just worldCorner, penetration )
                    else
                        ( prevContact, maxPenetration )
            )
            -- Initial state for (maybeContact, maxPenetration)
            ( Nothing, 0 )
        |> (\result ->
                Array.foldl
                    (foldSphereFaceContact
                        t1.position
                        radius
                        t2
                        vertices
                    )
                    result
                    faces
           )
        |> (\( oneFound, penetration ) ->
                case oneFound of
                    Just worldContact2 ->
                        let
                            worldNormal =
                                Vec3.normalize (Vec3.sub worldContact2 t1.position)
                        in
                            { bodyId1 = bodyId1
                            , bodyId2 = bodyId2
                            , ni = worldNormal
                            , ri =
                                Vec3.sub worldContact2 t1.position
                                    |> Vec3.add (Vec3.scale penetration worldNormal)
                            , rj = Vec3.sub worldContact2 t2.position
                            , restitution = 0
                            }
                                :: contactEquations

                    Nothing ->
                        contactEquations
           )


foldSphereFaceContact : Vec3 -> Float -> Transform -> Array Vec3 -> Face -> ( Maybe Vec3, Float ) -> ( Maybe Vec3, Float )
foldSphereFaceContact center radius t2 vertices { vertexIndices, normal } ( prevContact, maxPenetration ) =
    let
        -- Get world-transformed normal of the face
        worldFacePlaneNormal =
            Quaternion.rotate t2.quaternion normal

        -- Get an arbitrary world vertex from the face
        worldPoint =
            List.head vertexIndices
                |> Maybe.andThen (\i -> Array.get i vertices)
                |> Maybe.map
                    (Transform.pointToWorldFrame t2)

        penetration =
            worldPoint
                |> Maybe.map
                    (\point ->
                        worldFacePlaneNormal
                            |> Vec3.scale radius
                            |> Vec3.sub center
                            |> Vec3.sub point
                            |> Vec3.dot worldFacePlaneNormal
                    )
                |> Maybe.withDefault -1

        dot =
            worldPoint
                |> Maybe.map
                    (\point ->
                        Vec3.dot
                            (Vec3.sub center point)
                            worldFacePlaneNormal
                    )
                |> Maybe.withDefault -1

        worldVertices =
            if penetration >= maxPenetration && dot > 0 then
                -- Sphere intersects the face plane.
                vertexIndices
                    |> List.map
                        (\index ->
                            Array.get index vertices
                                |> Maybe.map
                                    (\vertex ->
                                        ( (Transform.pointToWorldFrame t2 vertex)
                                        , True
                                        )
                                    )
                                |> Maybe.withDefault ( Const.zero3, False )
                        )
                    |> (\tuples ->
                            -- Check that all the world vertices are valid.
                            if
                                tuples
                                    |> List.foldl
                                        (\tuple valid ->
                                            if valid then
                                                (Tuple.second tuple)
                                            else
                                                False
                                        )
                                        True
                            then
                                -- Extract the world vertices
                                tuples
                                    |> List.map Tuple.first
                            else
                                []
                       )
            else
                []
    in
        -- If vertices are valid, Check if the sphere center is inside the
        -- normal projection of the face polygon.
        if pointInPolygon worldVertices worldFacePlaneNormal center then
            let
                worldContact =
                    worldFacePlaneNormal
                        |> Vec3.scale (penetration - radius)
                        |> Vec3.add center
            in
                ( Just worldContact, penetration )
        else
            -- Try the edges
            foldSphereEdgeContact
                center
                radius
                (vertexIndices
                    |> List.map
                        (\index ->
                            Array.get index vertices
                                |> Maybe.map
                                    (Transform.pointToWorldFrame t2)
                        )
                )
                ( prevContact, maxPenetration )


foldSphereEdgeContact : Vec3 -> Float -> List (Maybe Vec3) -> ( Maybe Vec3, Float ) -> ( Maybe Vec3, Float )
foldSphereEdgeContact center radius worldVertices result =
    worldVertices
        |> listRingFoldStaggeredPairs
            (\current prev ( previousContact, maxPenetration ) ->
                case ( current, prev ) of
                    ( Just vertex, Just prevVertex ) ->
                        let
                            edge =
                                Vec3.sub vertex prevVertex

                            -- The normalized edge vector
                            edgeUnit =
                                Vec3.normalize edge

                            -- The potential contact is where the sphere center
                            -- projects onto the edge.
                            -- dot is the directed distance between the edge's
                            -- starting vertex and that projection. If it is not
                            -- between 0 and the edge's length, the projection
                            -- is invalid.
                            dot =
                                Vec3.dot (Vec3.sub center prevVertex) edgeUnit
                        in
                            if
                                (dot > 0)
                                    && (dot * dot < Vec3.lengthSquared edge)
                            then
                                let
                                    worldContact =
                                        Vec3.scale dot edgeUnit
                                            |> Vec3.add prevVertex

                                    penetration =
                                        radius - Vec3.distance worldContact center
                                in
                                    -- Edge collision only occurs if the
                                    -- projection is within the sphere.
                                    if penetration >= maxPenetration then
                                        ( Just worldContact, penetration )
                                    else
                                        ( previousContact, maxPenetration )
                            else
                                ( previousContact, maxPenetration )

                    _ ->
                        ( previousContact, maxPenetration )
            )
            result


{-| Map the function to pairs of consecutive elements in the ring array,
starting with the pair (first, last), then (second, first), and so on.
-}
listRingFoldStaggeredPairs : (a -> a -> b -> b) -> b -> List a -> b
listRingFoldStaggeredPairs fn acc list =
    case
        List.drop (List.length list - 1) list
            |> List.head
    of
        Nothing ->
            acc

        Just last ->
            listFoldStaggeredPairs fn last acc list


{-| Map the function to pairs of consecutive elements in the array,
starting with the pair (first, seed), then (second, first), and so on.
-}
listFoldStaggeredPairs : (a -> a -> b -> b) -> a -> b -> List a -> b
listFoldStaggeredPairs fn seed acc list =
    list
        |> List.foldl
            (\current ( acc1, staggered1 ) ->
                case staggered1 of
                    prev :: tail ->
                        ( fn current prev acc1
                        , tail
                        )

                    _ ->
                        -- impossible
                        ( acc1
                        , []
                        )
            )
            ( acc, seed :: list )
        |> Tuple.first


pointInPolygon : List Vec3 -> Vec3 -> Vec3 -> Bool
pointInPolygon vertices normal position =
    if List.length vertices < 3 then
        False
    else
        vertices
            |> listRingFoldStaggeredPairs
                (\vertex prevVertex ( acc, precedent ) ->
                    if acc then
                        let
                            edge =
                                Vec3.sub vertex prevVertex

                            edge_x_normal =
                                Vec3.cross edge normal

                            vertex_to_p =
                                Vec3.sub position prevVertex

                            -- This dot product determines which side
                            -- of the edge the point is.
                            -- It must be consistent for all edges for the
                            -- point to be within the face.
                            side =
                                (Vec3.dot edge_x_normal vertex_to_p) > 0
                        in
                            case precedent of
                                Nothing ->
                                    ( True
                                    , side |> Just
                                    )

                                Just determinedPrecedent ->
                                    ( side == determinedPrecedent
                                    , precedent
                                    )
                    else
                        ( False, Nothing )
                )
                ( True, Nothing )
            |> Tuple.first


addSphereSphereContacts : Transform -> Float -> BodyId -> Body -> Transform -> Float -> BodyId -> Body -> List ContactEquation -> List ContactEquation
addSphereSphereContacts t1 radius1 bodyId1 body1 t2 radius2 bodyId2 body2 contactEquations =
    let
        center1 =
            Transform.pointToWorldFrame t1 Const.zero3

        center2 =
            Transform.pointToWorldFrame t2 Const.zero3

        distance =
            Vec3.distance center2 center1
                - radius1
                - radius2

        normal =
            Vec3.direction center2 center1
    in
        if distance > 0 then
            contactEquations
        else
            { bodyId1 = bodyId1
            , bodyId2 = bodyId2
            , ni = normal
            , ri = Vec3.scale radius1 normal
            , rj = Vec3.scale -radius2 normal
            , restitution = 0
            }
                :: contactEquations


arrayFoldWhileNothing : (a -> Maybe b) -> Maybe b -> Array a -> Maybe b
arrayFoldWhileNothing fn seed array =
    array
        |> Array.foldl
            (\element acc ->
                case acc of
                    Nothing ->
                        fn element

                    _ ->
                        acc
            )
            seed
