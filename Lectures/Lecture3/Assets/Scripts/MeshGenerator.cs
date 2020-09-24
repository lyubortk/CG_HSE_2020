using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour {
    public MetaBallField Field = new MetaBallField();

    public Vector3 farCorner;
    public float boundingCubeEdge;
    public float smallCubeEdge;
    public float normalApproximationDelta;

    private float eps = 0.0001F;
    private MeshFilter _filter;
    private Mesh _mesh;
    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake() {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();
        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();
        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update() {
        vertices.Clear();
        indices.Clear();
        normals.Clear();

        Field.Update();

        for (float dx = 0; dx + smallCubeEdge <= boundingCubeEdge + eps; dx += smallCubeEdge) {
            for (float dy = 0; dy + smallCubeEdge <= boundingCubeEdge + eps; dy += smallCubeEdge) {
                for (float dz = 0; dz + smallCubeEdge <= boundingCubeEdge + eps; dz += smallCubeEdge) {
                    Vector3 smallCubeCorner = farCorner + new Vector3(dx, dy, dz);

                    int caseIndex = 0;
                    for (int vertexIndex = 0; vertexIndex < 8; vertexIndex++) {
                        Vector3 vertexPosition = smallCubeCorner + MarchingCubes.Tables._cubeVertices[vertexIndex] * smallCubeEdge;
                        float f = Field.F(vertexPosition);
                        if (f > 0) {
                            caseIndex |= 1 << vertexIndex;
                        }
                    }

                    int numberOfTriangles = MarchingCubes.Tables.CaseToTrianglesCount[caseIndex];

                    for (int triangleNum = 0; triangleNum < numberOfTriangles; triangleNum++) {
                        int3 edges = MarchingCubes.Tables.CaseToVertices[caseIndex][triangleNum];
                        processEdge(edges.x, smallCubeCorner);
                        processEdge(edges.y, smallCubeCorner);
                        processEdge(edges.z, smallCubeCorner);
                    }

                }
            }
        }

        // Here unity automatically assumes that vertices are points and hence (x, y, z) will be represented as (x, y, z, 1) in homogenous coordinates
        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.SetNormals(normals);

        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }

    private void processEdge(int edgeNum, Vector3 smallCubeCorner) {
        int[] edgeVertices = MarchingCubes.Tables._cubeEdges[edgeNum];
        Vector3 point1 = smallCubeCorner + MarchingCubes.Tables._cubeVertices[edgeVertices[0]] * smallCubeEdge;
        Vector3 point2 = smallCubeCorner + MarchingCubes.Tables._cubeVertices[edgeVertices[1]] * smallCubeEdge;
        float f1 = Field.F(point1);
        float f2 = Field.F(point2);
        Vector3 trianglePoint = Vector3.Lerp(point1, point2, -f1 / (f2 - f1));

        indices.Add(vertices.Count);
        vertices.Add(trianglePoint);

        Vector3 dx = new Vector3(normalApproximationDelta, 0, 0);
        Vector3 dy = new Vector3(0, normalApproximationDelta, 0);
        Vector3 dz = new Vector3(0, 0, normalApproximationDelta);

        Vector3 normal = -1 * Vector3.Normalize(new float3(
            Field.F(trianglePoint + dx) - Field.F(trianglePoint - dx),
            Field.F(trianglePoint + dy) - Field.F(trianglePoint - dy),
            Field.F(trianglePoint + dz) - Field.F(trianglePoint - dz)));
        normals.Add(normal);
    }
}