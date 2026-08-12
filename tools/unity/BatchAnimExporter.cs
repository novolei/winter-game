// Batch-export Unity .anim clips to FBX, one file per clip.
//
// WHY THIS EXISTS
// ---------------
// The Low Poly Animated Animals pack ships its dog animations as Unity-only
// `.anim` assets, keyed by a hash that standard CRC32 does not reproduce -- so
// Godot cannot read them and no converter is cheap. Unity itself is the only
// thing that can hand them over, and its FBX Exporter writes one take per file.
//
// Doing that by hand is seventeen trips through a modal dialog. This does it in
// one click, and names the files so the Godot side can slice them without
// guessing.
//
// SETUP
// -----
//   1. Any Unity project will do -- prefer a scratch one, not a project you
//      care about, since the package drops ~66 animals into Assets/.
//   2. Window > Package Manager > Unity Registry > "FBX Exporter" > Install.
//   3. Assets > Import Package > Custom Package... > the .unitypackage.
//      Importing only the dog folders is enough and much faster.
//   4. Drop this file anywhere under Assets/Editor/.
//
// USE
// ---
//   Select one or more model prefabs (or FBX assets) in the Project window,
//   then: Tools > WinterTime > Export Selected With All Clips.
//
//   For each selected model it finds every AnimationClip in the same folder
//   tree, and writes  <ModelName>@<ClipName>.fbx  into Assets/WinterTimeExport/.
//
//   The `Model@Clip` naming is not decoration: it is the convention Godot's
//   importer already understands, and it is how the wanderer's own animation
//   library was assembled.
//
// AFTERWARDS
// ----------
//   Copy Assets/WinterTimeExport/ across to the Godot project. Verify each take
//   actually MOVES rather than merely importing -- a clip that arrives with no
//   armature binding leaves the mesh in its bind pose, imports without error,
//   and is worse than a missing clip because the inventory will claim we have
//   it. That failure has already happened once on this project, with the crow.

#if UNITY_EDITOR
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Formats.Fbx.Exporter;
using UnityEngine;

public static class BatchAnimExporter
{
    const string OutputDir = "Assets/WinterTimeExport";

    [MenuItem("Tools/WinterTime/Export Selected With All Clips")]
    static void ExportSelected()
    {
        var models = Selection.GetFiltered<GameObject>(SelectionMode.Assets);
        if (models.Length == 0)
        {
            EditorUtility.DisplayDialog(
                "Nothing selected",
                "Select one or more model prefabs or FBX assets in the Project window first.",
                "OK");
            return;
        }

        Directory.CreateDirectory(OutputDir);
        int written = 0, skipped = 0;

        foreach (var model in models)
        {
            var modelPath = AssetDatabase.GetAssetPath(model);
            var folder = Path.GetDirectoryName(modelPath);
            var clips = FindClipsUnder(folder);

            if (clips.Count == 0)
            {
                Debug.LogWarning($"[WinterTime] No AnimationClips found near {modelPath} -- skipped.");
                skipped++;
                continue;
            }

            foreach (var clip in clips)
            {
                // A fresh instance per clip: the exporter writes whatever the
                // Animation component currently holds, so reusing one instance
                // would bake the same take every time.
                var instance = (GameObject)PrefabUtility.InstantiatePrefab(model);
                if (instance == null) instance = Object.Instantiate(model);

                var animation = instance.GetComponent<Animation>();
                if (animation == null) animation = instance.AddComponent<Animation>();
                animation.AddClip(clip, clip.name);
                animation.clip = clip;

                var outPath = Path.Combine(OutputDir, $"{model.name}@{clip.name}.fbx");
                ModelExporter.ExportObject(outPath, instance);
                Object.DestroyImmediate(instance);

                written++;
                Debug.Log($"[WinterTime] {outPath}");
            }
        }

        AssetDatabase.Refresh();
        EditorUtility.DisplayDialog(
            "WinterTime export",
            $"Wrote {written} FBX file(s) to {OutputDir}.\n" +
            $"{skipped} model(s) had no clips nearby.\n\n" +
            "Verify each take MOVES after importing, not merely that it imported.",
            "OK");
    }

    static List<AnimationClip> FindClipsUnder(string folder)
    {
        var found = new List<AnimationClip>();
        var seen = new HashSet<string>();

        foreach (var guid in AssetDatabase.FindAssets("t:AnimationClip", new[] { folder }))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid);
            foreach (var asset in AssetDatabase.LoadAllAssetsAtPath(path))
            {
                // Skip Unity's __preview__ clips, which are editor artefacts.
                if (asset is AnimationClip clip && !clip.name.StartsWith("__"))
                {
                    if (seen.Add(clip.name)) found.Add(clip);
                }
            }
        }
        return found;
    }
}
#endif
