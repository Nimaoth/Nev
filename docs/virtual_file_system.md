# Virtual file system (VFS)

Nev uses a virtual file system internally. The VFS is a tree of different types of file systems (local, in-memory, remote, etc.).

Here are the types of file systems that are supported:
- `VFS` - The base type for all other file systems, which can be used as a container/folder for other VFSs.
- `VFSInMemory` - This file system stores files in RAM.
- `VFSLocal` - This represents your local filesystem.
- `VFSLink` - This file system can link into a subfolder of another file systems. Cycles are not allowed.

By default Nev creates a VFS hierarchy which contains the local file system under `local://`, and some links into that for convenience:
- `app://` links to the directory when Nev is installed under `local://`
- `home://` links to the user home directory under `local://`
- `ws0://`, `ws1://` etc. link to the workspace folders.
- `ws://0`, `ws://1` etc. link to the workspace folders.
- `plugs://`, contains plugin sources (if available)

To explore the entire VFS in the builtin file explorer you can run the command `explore-file "" true` (to see some more info about the VFSs) or just `explore-files`

![alt](https://raw.githubusercontent.com/Nimaoth/AbsytreeScreenshots/main/vfs.png)

You can see the also VFS hierarchy by running the command `dump-vfs-hierarchy`, which will output something like this:
```
VFS()
  '' -> VFSLink(, VFSLocal(local://)/)
  'local://' -> VFSLocal(local://)
  'app://' -> VFSLink(app://, VFSLocal(local://)//home/xyz/Nev)
  'plugs://' -> VFS(plugs://)
    'keybindings_plugin' -> VFSInMemory(keybindings_plugin)
    'my_plugin' -> VFSInMemory(my_plugin)
  'ws://' -> VFS(ws://)
    '0' -> VFSLink(0, VFSLocal(local://)//home/xyz/my project)
  'home://' -> VFSLink(home://, VFSLocal(local://)//home/xyz)
  'ws0://' -> VFSLink(ws0://, VFSLocal(local://)//home/xyz/my project)
```
Here is a visual representation.

<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1120pt" height="606pt" viewBox="0.00 0.00 1119.51 605.85">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 601.8526)">
<title>DFA</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-601.8526 1115.5093,-601.8526 1115.5093,4 -4,4"/>
<!-- VFS\nroot -->
<g id="node1" class="node">
<title>VFS\nroot</title>
<ellipse fill="none" stroke="#ffa500" cx="496.0424" cy="-568.437" rx="29.4329" ry="29.3315"/>
<text text-anchor="middle" x="496.0424" y="-572.637" font-family="Times,serif" font-size="14.00" fill="#000000">VFS</text>
<text text-anchor="middle" x="496.0424" y="-555.837" font-family="Times,serif" font-size="14.00" fill="#000000">root</text>
</g>
<!-- VFS\nPlugin sources -->
<g id="node2" class="node">
<title>VFS\nPlugin sources</title>
<ellipse fill="none" stroke="#ffa500" cx="100.0424" cy="-456.8057" rx="69.1539" ry="29.3315"/>
<text text-anchor="middle" x="100.0424" y="-461.0057" font-family="Times,serif" font-size="14.00" fill="#000000">VFS</text>
<text text-anchor="middle" x="100.0424" y="-444.2057" font-family="Times,serif" font-size="14.00" fill="#000000">Plugin sources</text>
</g>
<!-- VFS\nroot&#45;&gt;VFS\nPlugin sources -->
<g id="edge17" class="edge">
<title>VFS\nroot-&gt;VFS\nPlugin sources</title>
<path fill="none" stroke="#000000" d="M466.4637,-566.3809C415.3539,-562.1615 307.724,-550.3269 221.7142,-521.0214 196.18,-512.3213 169.4946,-498.7993 147.6434,-486.4032"/>
<polygon fill="#000000" stroke="#000000" points="149.3133,-483.3259 138.9025,-481.3592 145.8145,-489.3889 149.3133,-483.3259"/>
<text text-anchor="middle" x="247.7065" y="-508.4214" font-family="Times,serif" font-size="14.00" fill="#000000">'plugs://'</text>
</g>
<!-- VFSLink\nForward to local\n -->
<g id="node4" class="node">
<title>VFSLink\nForward to local\n</title>
<ellipse fill="none" stroke="#00ff00" cx="601.0424" cy="-333.295" rx="76.9797" ry="29.3315"/>
<text text-anchor="middle" x="601.0424" y="-337.495" font-family="Times,serif" font-size="14.00" fill="#000000">VFSLink</text>
<text text-anchor="middle" x="601.0424" y="-320.695" font-family="Times,serif" font-size="14.00" fill="#000000">Forward to local</text>
</g>
<!-- VFS\nroot&#45;&gt;VFSLink\nForward to local\n -->
<g id="edge1" class="edge">
<title>VFS\nroot-&gt;VFSLink\nForward to local\n</title>
<path fill="none" stroke="#000000" d="M508.0872,-541.4632C526.6831,-499.8186 562.4612,-419.6955 583.7973,-371.9145"/>
<polygon fill="#000000" stroke="#000000" points="587.1095,-373.0809 587.9911,-362.5228 580.7178,-370.2267 587.1095,-373.0809"/>
<text text-anchor="middle" x="563.703" y="-452.6057" font-family="Times,serif" font-size="14.00" fill="#000000">''</text>
</g>
<!-- VFSLink\nApp directory\n/home/xyz/Nev -->
<g id="node5" class="node">
<title>VFSLink\nApp directory\n/home/xyz/Nev</title>
<ellipse fill="none" stroke="#00ff00" cx="230.0424" cy="-333.295" rx="72.1925" ry="41.0911"/>
<text text-anchor="middle" x="230.0424" y="-345.895" font-family="Times,serif" font-size="14.00" fill="#000000">VFSLink</text>
<text text-anchor="middle" x="230.0424" y="-329.095" font-family="Times,serif" font-size="14.00" fill="#000000">App directory</text>
<text text-anchor="middle" x="230.0424" y="-312.295" font-family="Times,serif" font-size="14.00" fill="#000000">/home/xyz/Nev</text>
</g>
<!-- VFS\nroot&#45;&gt;VFSLink\nApp directory\n/home/xyz/Nev -->
<g id="edge11" class="edge">
<title>VFS\nroot-&gt;VFSLink\nApp directory\n/home/xyz/Nev</title>
<path fill="none" stroke="#000000" d="M469.6444,-554.8623C442.0237,-540.0031 398.1309,-514.4975 364.8348,-486.2214 327.1591,-454.226 290.4729,-411.6248 264.9102,-379.5131"/>
<polygon fill="#000000" stroke="#000000" points="267.5991,-377.2705 258.6571,-371.588 262.1037,-381.6065 267.5991,-377.2705"/>
<text text-anchor="middle" x="385.6462" y="-452.6057" font-family="Times,serif" font-size="14.00" fill="#000000">'app://'</text>
</g>
<!-- VFSLink\nHome directory\n/home/xyz -->
<g id="node6" class="node">
<title>VFSLink\nHome directory\n/home/xyz</title>
<ellipse fill="none" stroke="#00ff00" cx="394.0424" cy="-333.295" rx="73.923" ry="41.0911"/>
<text text-anchor="middle" x="394.0424" y="-345.895" font-family="Times,serif" font-size="14.00" fill="#000000">VFSLink</text>
<text text-anchor="middle" x="394.0424" y="-329.095" font-family="Times,serif" font-size="14.00" fill="#000000">Home directory</text>
<text text-anchor="middle" x="394.0424" y="-312.295" font-family="Times,serif" font-size="14.00" fill="#000000">/home/xyz</text>
</g>
<!-- VFS\nroot&#45;&gt;VFSLink\nHome directory\n/home/xyz -->
<g id="edge14" class="edge">
<title>VFS\nroot-&gt;VFSLink\nHome directory\n/home/xyz</title>
<path fill="none" stroke="#000000" d="M474.8652,-547.6207C460.168,-532.0141 441.2664,-509.4303 429.9442,-486.2214 414.3672,-454.2907 405.3467,-415.2561 400.2437,-384.6164"/>
<polygon fill="#000000" stroke="#000000" points="403.6744,-383.9026 398.6594,-374.5698 396.7599,-384.993 403.6744,-383.9026"/>
<text text-anchor="middle" x="456.0915" y="-452.6057" font-family="Times,serif" font-size="14.00" fill="#000000">'home://'</text>
</g>
<!-- VFSLink\nFirst workspace folder\n/home/xyz/my project -->
<g id="node7" class="node">
<title>VFSLink\nFirst workspace folder\n/home/xyz/my project</title>
<ellipse fill="none" stroke="#00ff00" cx="796.0424" cy="-333.295" rx="100.2492" ry="41.0911"/>
<text text-anchor="middle" x="796.0424" y="-345.895" font-family="Times,serif" font-size="14.00" fill="#000000">VFSLink</text>
<text text-anchor="middle" x="796.0424" y="-329.095" font-family="Times,serif" font-size="14.00" fill="#000000">First workspace folder</text>
<text text-anchor="middle" x="796.0424" y="-312.295" font-family="Times,serif" font-size="14.00" fill="#000000">/home/xyz/my project</text>
</g>
<!-- VFS\nroot&#45;&gt;VFSLink\nFirst workspace folder\n/home/xyz/my project -->
<g id="edge19" class="edge">
<title>VFS\nroot-&gt;VFSLink\nFirst workspace folder\n/home/xyz/my project</title>
<path fill="none" stroke="#000000" d="M519.5829,-549.9858C566.9387,-512.868 674.831,-428.3013 740.9561,-376.472"/>
<polygon fill="#000000" stroke="#000000" points="743.4921,-378.9314 749.2034,-370.0077 739.1738,-373.422 743.4921,-378.9314"/>
<text text-anchor="middle" x="696.8145" y="-452.6057" font-family="Times,serif" font-size="14.00" fill="#000000">'ws0://'</text>
</g>
<!-- VFSLocal\n -->
<g id="node8" class="node">
<title>VFSLocal\n</title>
<ellipse fill="none" stroke="#0000ff" cx="578.0424" cy="-237" rx="50.9599" ry="18"/>
<text text-anchor="middle" x="578.0424" y="-232.8" font-family="Times,serif" font-size="14.00" fill="#000000">VFSLocal</text>
</g>
<!-- VFS\nroot&#45;&gt;VFSLocal\n -->
<g id="edge10" class="edge">
<title>VFS\nroot-&gt;VFSLocal\n</title>
<path fill="none" stroke="#000000" d="M491.0746,-539.1131C483.6175,-486.4849 474.3949,-373.8652 515.0424,-292 521.5891,-278.8148 532.8323,-267.4464 544.0249,-258.524"/>
<polygon fill="#000000" stroke="#000000" points="546.1986,-261.2687 552.0981,-252.4683 541.9982,-255.669 546.1986,-261.2687"/>
<text text-anchor="middle" x="512.1441" y="-396.7901" font-family="Times,serif" font-size="14.00" fill="#000000">'local://'</text>
</g>
<!-- VFS\nWorkspace folders -->
<g id="node15" class="node">
<title>VFS\nWorkspace folders</title>
<ellipse fill="none" stroke="#000000" cx="951.0424" cy="-456.8057" rx="85.5935" ry="29.3315"/>
<text text-anchor="middle" x="951.0424" y="-461.0057" font-family="Times,serif" font-size="14.00" fill="#000000">VFS</text>
<text text-anchor="middle" x="951.0424" y="-444.2057" font-family="Times,serif" font-size="14.00" fill="#000000">Workspace folders</text>
</g>
<!-- VFS\nroot&#45;&gt;VFS\nWorkspace folders -->
<g id="edge22" class="edge">
<title>VFS\nroot-&gt;VFS\nWorkspace folders</title>
<path fill="none" stroke="#000000" d="M525.3,-563.5385C570.5455,-555.7598 660.0989,-539.5529 735.0424,-521.0214 783.3868,-509.0671 837.0598,-493.1237 878.8089,-480.1141"/>
<polygon fill="#000000" stroke="#000000" points="880.1135,-483.3732 888.611,-477.0453 878.022,-476.693 880.1135,-483.3732"/>
<text text-anchor="middle" x="812.3145" y="-508.4214" font-family="Times,serif" font-size="14.00" fill="#000000">'ws://'</text>
</g>
<!-- VFSInMemory\n -->
<g id="node3" class="node">
<title>VFSInMemory\n</title>
<ellipse fill="none" stroke="#a020f0" cx="70.0424" cy="-333.295" rx="70.0848" ry="18"/>
<text text-anchor="middle" x="70.0424" y="-329.095" font-family="Times,serif" font-size="14.00" fill="#000000">VFSInMemory</text>
</g>
<!-- VFS\nPlugin sources&#45;&gt;VFSInMemory\n -->
<g id="edge18" class="edge">
<title>VFS\nPlugin sources-&gt;VFSInMemory\n</title>
<path fill="none" stroke="#000000" d="M92.9328,-427.5354C88.0566,-407.46 81.6252,-380.9819 76.8215,-361.2048"/>
<polygon fill="#000000" stroke="#000000" points="80.1691,-360.1583 74.4076,-351.2669 73.3669,-361.8105 80.1691,-360.1583"/>
<text text-anchor="middle" x="148.3138" y="-396.7901" font-family="Times,serif" font-size="14.00" fill="#000000">'keybindings_plugin'</text>
</g>
<!-- VFSLink\nForward to local\n&#45;&gt;VFSLocal\n -->
<g id="edge2" class="edge">
<title>VFSLink\nForward to local\n-&gt;VFSLocal\n</title>
<path fill="none" stroke="#ff0000" d="M587.8196,-304.142C584.2045,-291.8115 580.8031,-277.5017 578.5841,-265.2685"/>
<polygon fill="#ff0000" stroke="#ff0000" points="582.0016,-264.4747 576.9628,-255.1548 575.0898,-265.5827 582.0016,-264.4747"/>
</g>
<!-- VFSLink\nForward to local\n&#45;&gt;VFSLocal\n -->
<g id="edge3" class="edge">
<title>VFSLink\nForward to local\n-&gt;VFSLocal\n</title>
<path fill="none" stroke="#ffff00" d="M600.2904,-303.8801C597.9668,-291.349 594.4584,-276.8122 590.7753,-264.4985"/>
<polygon fill="#ffff00" stroke="#ffff00" points="594.0437,-263.2283 587.6625,-254.7707 587.3767,-265.3617 594.0437,-263.2283"/>
</g>
<!-- VFSLink\nApp directory\n/home/xyz/Nev&#45;&gt;VFSLocal\n -->
<g id="edge12" class="edge">
<title>VFSLink\nApp directory\n/home/xyz/Nev-&gt;VFSLocal\n</title>
<path fill="none" stroke="#ff0000" d="M281.86,-304.3052C291.3734,-299.729 301.3606,-295.3955 311.0424,-292 380.8348,-267.5229 464.9137,-252.4343 519.8294,-244.3931"/>
<polygon fill="#ff0000" stroke="#ff0000" points="520.332,-247.8569 529.734,-242.973 519.3384,-240.9278 520.332,-247.8569"/>
</g>
<!-- Nev -->
<g id="node11" class="node">
<title>Nev</title>
<ellipse fill="none" stroke="#000000" cx="338.0424" cy="-18" rx="27.2467" ry="18"/>
<text text-anchor="middle" x="338.0424" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">Nev</text>
</g>
<!-- VFSLink\nApp directory\n/home/xyz/Nev&#45;&gt;Nev -->
<g id="edge13" class="edge">
<title>VFSLink\nApp directory\n/home/xyz/Nev-&gt;Nev</title>
<path fill="none" stroke="#ffff00" d="M239.9021,-292.3068C243.1947,-275.3011 246.0424,-255.3029 246.0424,-237 246.0424,-237 246.0424,-237 246.0424,-91 246.0424,-60.3106 277.8456,-40.4738 304.0545,-29.3369"/>
<polygon fill="#ffff00" stroke="#ffff00" points="305.3903,-32.5724 313.3881,-25.6235 302.8026,-26.0682 305.3903,-32.5724"/>
</g>
<!-- VFSLink\nHome directory\n/home/xyz&#45;&gt;VFSLocal\n -->
<g id="edge15" class="edge">
<title>VFSLink\nHome directory\n/home/xyz-&gt;VFSLocal\n</title>
<path fill="none" stroke="#ff0000" d="M438.4087,-299.8209C451.9898,-290.4291 467.256,-280.693 482.0424,-273 497.2113,-265.108 514.5137,-258.0697 530.2125,-252.3558"/>
<polygon fill="#ff0000" stroke="#ff0000" points="531.4924,-255.6155 539.7466,-248.9733 529.1519,-249.0184 531.4924,-255.6155"/>
</g>
<!-- xyz -->
<g id="node10" class="node">
<title>xyz</title>
<ellipse fill="none" stroke="#000000" cx="430.0424" cy="-91" rx="27" ry="18"/>
<text text-anchor="middle" x="430.0424" y="-86.8" font-family="Times,serif" font-size="14.00" fill="#000000">xyz</text>
</g>
<!-- VFSLink\nHome directory\n/home/xyz&#45;&gt;xyz -->
<g id="edge16" class="edge">
<title>VFSLink\nHome directory\n/home/xyz-&gt;xyz</title>
<path fill="none" stroke="#ffff00" d="M400.1901,-291.9183C407.5213,-242.5762 419.5745,-161.4529 425.889,-118.9541"/>
<polygon fill="#ffff00" stroke="#ffff00" points="429.3566,-119.4302 427.3643,-109.0244 422.4326,-118.4014 429.3566,-119.4302"/>
</g>
<!-- VFSLink\nFirst workspace folder\n/home/xyz/my project&#45;&gt;VFSLocal\n -->
<g id="edge20" class="edge">
<title>VFSLink\nFirst workspace folder\n/home/xyz/my project-&gt;VFSLocal\n</title>
<path fill="none" stroke="#ff0000" d="M727.365,-302.9589C691.8907,-287.2891 649.7833,-268.6894 619.3405,-255.2422"/>
<polygon fill="#ff0000" stroke="#ff0000" points="620.4511,-251.9066 609.8896,-251.0676 617.6227,-258.3097 620.4511,-251.9066"/>
</g>
<!-- my project -->
<g id="node12" class="node">
<title>my project</title>
<ellipse fill="none" stroke="#000000" cx="796.0424" cy="-18" rx="52.7079" ry="18"/>
<text text-anchor="middle" x="796.0424" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">my project</text>
</g>
<!-- VFSLink\nFirst workspace folder\n/home/xyz/my project&#45;&gt;my project -->
<g id="edge21" class="edge">
<title>VFSLink\nFirst workspace folder\n/home/xyz/my project-&gt;my project</title>
<path fill="none" stroke="#ffff00" d="M796.0424,-291.5844C796.0424,-274.6455 796.0424,-254.8881 796.0424,-237 796.0424,-237 796.0424,-237 796.0424,-91 796.0424,-76.2996 796.0424,-59.934 796.0424,-46.4302"/>
<polygon fill="#ffff00" stroke="#ffff00" points="799.5425,-46.3003 796.0424,-36.3003 792.5425,-46.3004 799.5425,-46.3003"/>
</g>
<!-- home -->
<g id="node9" class="node">
<title>home</title>
<ellipse fill="none" stroke="#000000" cx="482.0424" cy="-164" rx="32.4846" ry="18"/>
<text text-anchor="middle" x="482.0424" y="-159.8" font-family="Times,serif" font-size="14.00" fill="#000000">home</text>
</g>
<!-- VFSLocal\n&#45;&gt;home -->
<g id="edge4" class="edge">
<title>VFSLocal\n-&gt;home</title>
<path fill="none" stroke="#c0c0c0" d="M556.2585,-220.4352C542.4777,-209.956 524.5381,-196.3144 509.7488,-185.0684"/>
<polygon fill="#c0c0c0" stroke="#c0c0c0" points="511.539,-182.0327 501.4604,-178.7658 507.3019,-187.6048 511.539,-182.0327"/>
</g>
<!-- root -->
<g id="node13" class="node">
<title>root</title>
<ellipse fill="none" stroke="#000000" cx="563.0424" cy="-164" rx="27" ry="18"/>
<text text-anchor="middle" x="563.0424" y="-159.8" font-family="Times,serif" font-size="14.00" fill="#000000">root</text>
</g>
<!-- VFSLocal\n&#45;&gt;root -->
<g id="edge8" class="edge">
<title>VFSLocal\n-&gt;root</title>
<path fill="none" stroke="#c0c0c0" d="M574.3345,-218.9551C572.6452,-210.7337 570.6076,-200.8173 568.7309,-191.6841"/>
<polygon fill="#c0c0c0" stroke="#c0c0c0" points="572.1488,-190.9282 566.7076,-181.8374 565.292,-192.3372 572.1488,-190.9282"/>
</g>
<!-- ... -->
<g id="node14" class="node">
<title>...</title>
<ellipse fill="none" stroke="#000000" cx="635.0424" cy="-164" rx="27" ry="18"/>
<text text-anchor="middle" x="635.0424" y="-159.8" font-family="Times,serif" font-size="14.00" fill="#000000">...</text>
</g>
<!-- VFSLocal\n&#45;&gt;... -->
<g id="edge9" class="edge">
<title>VFSLocal\n-&gt;...</title>
<path fill="none" stroke="#c0c0c0" d="M591.8405,-219.3287C599.1508,-209.9664 608.2382,-198.3281 616.1897,-188.1446"/>
<polygon fill="#c0c0c0" stroke="#c0c0c0" points="619.1422,-190.0505 622.5379,-180.0145 613.6248,-185.7424 619.1422,-190.0505"/>
</g>
<!-- home&#45;&gt;xyz -->
<g id="edge5" class="edge">
<title>home-&gt;xyz</title>
<path fill="none" stroke="#c0c0c0" d="M469.9818,-147.0688C463.325,-137.7237 454.9373,-125.9487 447.569,-115.6048"/>
<polygon fill="#c0c0c0" stroke="#c0c0c0" points="450.3324,-113.4514 441.6798,-107.3372 444.631,-117.5127 450.3324,-113.4514"/>
</g>
<!-- xyz&#45;&gt;Nev -->
<g id="edge6" class="edge">
<title>xyz-&gt;Nev</title>
<path fill="none" stroke="#c0c0c0" d="M412.3038,-76.9249C398.5582,-66.018 379.3157,-50.7495 363.8626,-38.4878"/>
<polygon fill="#c0c0c0" stroke="#c0c0c0" points="365.7355,-35.506 355.7264,-32.0319 361.3845,-40.9895 365.7355,-35.506"/>
</g>
<!-- xyz&#45;&gt;my project -->
<g id="edge7" class="edge">
<title>xyz-&gt;my project</title>
<path fill="none" stroke="#c0c0c0" d="M456.0708,-85.8085C515.1143,-74.0321 660.2885,-45.0766 740.5149,-29.0751"/>
<polygon fill="#c0c0c0" stroke="#c0c0c0" points="741.3183,-32.4839 750.4405,-27.0955 739.949,-25.6192 741.3183,-32.4839"/>
</g>
<!-- VFSLink\nWorkspace 0\n/home/xyz/my project -->
<g id="node16" class="node">
<title>VFSLink\nWorkspace 0\n/home/xyz/my project</title>
<ellipse fill="none" stroke="#000000" cx="1013.0424" cy="-333.295" rx="98.4338" ry="41.0911"/>
<text text-anchor="middle" x="1013.0424" y="-345.895" font-family="Times,serif" font-size="14.00" fill="#000000">VFSLink</text>
<text text-anchor="middle" x="1013.0424" y="-329.095" font-family="Times,serif" font-size="14.00" fill="#000000">Workspace 0</text>
<text text-anchor="middle" x="1013.0424" y="-312.295" font-family="Times,serif" font-size="14.00" fill="#000000">/home/xyz/my project</text>
</g>
<!-- VFS\nWorkspace folders&#45;&gt;VFSLink\nWorkspace 0\n/home/xyz/my project -->
<g id="edge23" class="edge">
<title>VFS\nWorkspace folders-&gt;VFSLink\nWorkspace 0\n/home/xyz/my project</title>
<path fill="none" stroke="#000000" d="M965.7355,-427.5354C972.3781,-414.3027 980.4171,-398.2881 987.9688,-383.2444"/>
<polygon fill="#000000" stroke="#000000" points="991.2326,-384.5439 992.5909,-374.0365 984.9766,-381.4035 991.2326,-384.5439"/>
<text text-anchor="middle" x="990.203" y="-396.7901" font-family="Times,serif" font-size="14.00" fill="#000000">'0'</text>
</g>
<!-- VFSLink\nWorkspace 0\n/home/xyz/my project&#45;&gt;VFSLocal\n -->
<g id="edge24" class="edge">
<title>VFSLink\nWorkspace 0\n/home/xyz/my project-&gt;VFSLocal\n</title>
<path fill="none" stroke="#ff0000" d="M942.8351,-304.1498C930.3859,-299.6453 917.4381,-295.3763 905.0424,-292 813.0388,-266.9407 703.1965,-251.2841 637.1163,-243.3535"/>
<polygon fill="#ff0000" stroke="#ff0000" points="637.2375,-239.8436 626.896,-242.1468 636.4166,-246.7953 637.2375,-239.8436"/>
</g>
<!-- VFSLink\nWorkspace 0\n/home/xyz/my project&#45;&gt;my project -->
<g id="edge25" class="edge">
<title>VFSLink\nWorkspace 0\n/home/xyz/my project-&gt;my project</title>
<path fill="none" stroke="#ffff00" d="M986.9208,-293.2383C978.3797,-276.5399 971.0424,-256.5156 971.0424,-237 971.0424,-237 971.0424,-237 971.0424,-91 971.0424,-64.6131 902.4157,-42.6471 851.1133,-29.9128"/>
<polygon fill="#ffff00" stroke="#ffff00" points="851.6521,-26.4422 841.1092,-27.4905 850.0047,-33.2456 851.6521,-26.4422"/>
</g>
</g>
</svg>

With the given VFS, the following paths would refer to these files:

| VFS Path                    | Normalized path        | Explanation |
| -------------------------   | -------------- | - |
| `local:///home/xyz/Nev/nev.exe`        | `local:///home/xyz/Nev/nev.exe`       | The `local://` prefix refers to a VFSLocal, which itself doesn't link to other VFSs. |
| `/home/xyz/Nev/nev.exe`                | `local:///home/xyz/Nev/nev.exe`       | This path doesn't match any of the prefixes of the form `xyz://`, but it does match the VFSLink with an empty prefix, which in turn links to the VFSLocal |
| `home://Nev/nev.exe`        | `local:///home/xyz/Nev/nev.exe`       | The `home://` prefix refers to `local:///home/xyz`, add to that `Nev/nev.exe` |
| `app://nev.exe`        | `local:///home/xyz/Nev/nev.exe`       | The `app://` prefix refers to `local:///home/xyz/Nev`, add to that `nev.exe` |
| `ws0://foo.txt`        | `local:///home/xyz/my project/foo.txt`       | The `ws0://` prefix refers to `local:///home/xyz/my project`, add to that `foo.txt` |
| `ws://0/foo.txt`        | `local:///home/xyz/my project/foo.txt`       | The `ws://` prefix refers to a sub VFS, and in there the `0` prefix refers to `local:///home/xyz/my project`, add to that `foo.txt` |
| `plugs://keybindings_plugin/src.nim`        | `plugs://keybindings_plugin/src.nim`       | The `plugs://` prefix refers to a sub VFS, and in there the `keybindings_plugin` prefix refers to an in memory VFS |

## Mounting VFSs

The `mount-vfs` command can be used to mount new VFSs in the VFS hierarchy:

```
mount-vfs <parent vfs path> <prefix within parent> <vfs config>
```

## Examples

### Mount the nimble packages directory under `nimble://` to have quick access to nim library source code:
```json
// ~/.nev/settings.json
{
    "+wasm-plugin-post-load-commands": [ // Run these commands after loading wasm plugins
        [
            "mount-vfs",
            null, // Null means mount under the root. If a path is provided then it will be mounted under the VFS the given path resolves to.
            "nimble://", // The prefix under which to mount the new VFS
            { // VFS description
                "type": "link", // create a VFSLink
                "target": "home://", // path of the target VFS to link to
                "targetPrefix": ".nimble/pkgs2" // Subdirectory within the target VFS
            }
        ]
    ]
}
```
After running this command the path `nimble://package_name/package.nim` would refer to `home://.nimble/pkgs2/package_name/package.nim`, which in turn refers to `local:///home/xyz/.nimble/pkgs2/package_name/package.nim`

### Mount a local folder as plugin source.
The `browse-keybinds` finder shows you the source code which defined keybindings (if available). It reads this source code from `plugs://<plugin_name>/<source_file>.nim`, which by default is mounted as an in memory VFS, containing embedded source code from the wasm binary.

If you develop you're own plugin you might want that to link to you're source code on your local file system instead.

To do this you can remount the filesystem for your plugin like this:
```json
// ~/.nev/settings.json
{
    "+wasm-plugin-post-load-commands": [ // Run these commands after loading wasm plugins
        [
            "mount-vfs",
            "plugs://", // Mount the new VFS under the VFS with the prefix 'plugs://'
            "my_plugin", // The prefix under which to mount the new VFS
            { // VFS description
                "type": "link", // create a VFSLink
                "target": "local://", // path of the target VFS to link to, you could also use app:// or home:// or whatever.
                "targetPrefix": "/path/to/plugin/source" // Subdirectory within the target VFS
            }
        ]
    ]
}
```
After running this command the path `plugs://my_plugin/source.nim` would not refer to the in-memory VFS anymore but to `local:///path/to/plugin/source/source.nim` instead.
