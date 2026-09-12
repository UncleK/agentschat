"use client";
import { useEffect, useRef, useState } from "react";
import { Pause, Play } from "lucide-react";
export function NetworkScene() {
  const mount = useRef<HTMLDivElement>(null),
    pausedRef = useRef(false);
  const [paused, setPaused] = useState(false),
    [ready, setReady] = useState(false);
  useEffect(() => {
    let cancelled = false,
      teardown = () => {};
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    async function setup() {
      const THREE = await import("three");
      if (cancelled || !mount.current) return;
      const host = mount.current;
      let renderer: InstanceType<typeof THREE.WebGLRenderer>;
      try {
        renderer = new THREE.WebGLRenderer({
          alpha: true,
          antialias: true,
          powerPreference: "low-power",
        });
      } catch {
        return;
      }
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.6));
      renderer.setClearColor(0, 0);
      host.appendChild(renderer.domElement);
      renderer.domElement.setAttribute("aria-hidden", "true");
      const scene = new THREE.Scene(),
        camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
      camera.position.set(0, 0.1, 7.2);
      const group = new THREE.Group();
      group.rotation.z = -0.17;
      scene.add(group);
      const resources: Array<{ dispose: () => void }> = [],
        positions: number[] = [],
        colors: number[] = [],
        nodes: InstanceType<typeof THREE.Vector3>[] = [];
      const mint = new THREE.Color("#77ffcf"),
        gold = new THREE.Color("#facd7c"),
        count = 420,
        angle = Math.PI * (3 - Math.sqrt(5));
      for (let i = 0; i < count; i++) {
        const y = 1 - (i / (count - 1)) * 2,
          r = Math.sqrt(1 - y * y),
          theta = angle * i,
          p = new THREE.Vector3(
            Math.cos(theta) * r * 2,
            y * 2,
            Math.sin(theta) * r * 2,
          );
        nodes.push(p);
        positions.push(p.x, p.y, p.z);
        const c = i % 11 === 0 ? gold : mint;
        colors.push(c.r, c.g, c.b);
      }
      const geom = new THREE.BufferGeometry();
      geom.setAttribute(
        "position",
        new THREE.Float32BufferAttribute(positions, 3),
      );
      geom.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
      const material = new THREE.ShaderMaterial({
        transparent: true,
        depthWrite: false,
        vertexColors: true,
        blending: THREE.AdditiveBlending,
        vertexShader:
          "varying vec3 vColor; void main(){vColor=color;vec4 mv=modelViewMatrix*vec4(position,1.0);gl_PointSize=20.0/(-mv.z);gl_Position=projectionMatrix*mv;}",
        fragmentShader:
          "varying vec3 vColor;void main(){float d=length(gl_PointCoord-0.5);if(d>0.5)discard;float a=pow(1.0-d*2.0,2.0);gl_FragColor=vec4(vColor,a);}",
      });
      group.add(new THREE.Points(geom, material));
      resources.push(geom, material);
      const lines: number[] = [];
      for (let i = 0; i < count; i += 2)
        for (let j = i + 1; j < count; j++)
          if (nodes[i].distanceTo(nodes[j]) < 0.36)
            lines.push(...nodes[i].toArray(), ...nodes[j].toArray());
      const lg = new THREE.BufferGeometry();
      lg.setAttribute("position", new THREE.Float32BufferAttribute(lines, 3));
      const lm = new THREE.LineBasicMaterial({
        color: mint,
        transparent: true,
        opacity: 0.13,
      });
      group.add(new THREE.LineSegments(lg, lm));
      resources.push(lg, lm);
      for (let i = 0; i < 3; i++) {
        const pts = [];
        for (let j = 0; j <= 160; j++) {
          const t = (j / 160) * Math.PI * 2;
          pts.push(new THREE.Vector3(Math.cos(t) * 2.3, Math.sin(t) * 2.3, 0));
        }
        const g = new THREE.BufferGeometry().setFromPoints(pts),
          m = new THREE.LineBasicMaterial({
            color: i === 1 ? gold : mint,
            transparent: true,
            opacity: i === 1 ? 0.25 : 0.16,
          }),
          ring = new THREE.Line(g, m);
        ring.rotation.set(0.55 + i * 0.7, 0.6 + i * 0.8, i * 0.2);
        group.add(ring);
        resources.push(g, m);
      }
      const cg = new THREE.IcosahedronGeometry(0.66, 1),
        cm = new THREE.MeshStandardMaterial({
          color: "#102a27",
          emissive: "#155e50",
          emissiveIntensity: 0.7,
          metalness: 0.8,
          roughness: 0.25,
          flatShading: true,
        }),
        core = new THREE.Mesh(cg, cm);
      group.add(core);
      resources.push(cg, cm);
      const eg = new THREE.EdgesGeometry(cg),
        em = new THREE.LineBasicMaterial({
          color: mint,
          transparent: true,
          opacity: 0.6,
        });
      core.add(new THREE.LineSegments(eg, em));
      resources.push(eg, em);
      scene.add(new THREE.AmbientLight("#c0ffe6", 2));
      const light = new THREE.PointLight("#83ffcb", 22);
      light.position.set(3, 4, 4);
      scene.add(light);
      const sg = new THREE.IcosahedronGeometry(0.095, 1),
        sm = new THREE.MeshStandardMaterial({
          color: "#a0ffdb",
          emissive: "#4cecba",
          emissiveIntensity: 1.6,
          metalness: 0.2,
          roughness: 0.5,
        });
      const satellites = [0, 1, 2, 3, 4].map(() => {
        const m = new THREE.Mesh(sg, sm);
        group.add(m);
        return m;
      });
      resources.push(sg, sm);
      const resize = () => {
        if (!host.clientWidth) return;
        renderer.setSize(host.clientWidth, host.clientHeight);
        camera.aspect = host.clientWidth / host.clientHeight;
        camera.updateProjectionMatrix();
        renderer.render(scene, camera);
      };
      const observer = new ResizeObserver(resize);
      observer.observe(host);
      let visible = true,
        pointerX = 0,
        pointerY = 0,
        last = 0,
        elapsed = 0,
        staticRendered = false;
      const intersection = new IntersectionObserver((e) => {
        visible = e[0].isIntersecting;
      });
      intersection.observe(host);
      const move = (e: PointerEvent) => {
        const r = host.getBoundingClientRect();
        pointerX = ((e.clientX - r.left) / r.width - 0.5) * 0.25;
        pointerY = ((e.clientY - r.top) / r.height - 0.5) * 0.2;
      };
      host.addEventListener("pointermove", move);
      const lost = (e: Event) => {
        e.preventDefault();
        setReady(false);
      };
      renderer.domElement.addEventListener("webglcontextlost", lost);
      renderer.setAnimationLoop((time) => {
        const delta = last ? Math.min((time - last) / 1000, 0.05) : 0;
        last = time;
        if (!visible || document.hidden) return;
        const animate = !pausedRef.current && !reduced.matches;
        if (!animate && staticRendered) return;
        if (animate) {
          elapsed += delta;
          group.rotation.y = elapsed * 0.075 + pointerX;
          group.rotation.x += (pointerY - group.rotation.x) * 0.03;
          core.rotation.y = elapsed * 0.14;
          core.rotation.x = elapsed * 0.11;
        }
        satellites.forEach((s, i) => {
          const a = elapsed * 0.12 + i * Math.PI * 0.4;
          s.position.set(
            Math.cos(a) * 2.3,
            Math.sin(a) * 1.15,
            Math.sin(a) * 1.95,
          );
        });
        renderer.render(scene, camera);
        staticRendered = !animate;
      });
      resize();
      setReady(true);
      teardown = () => {
        renderer.setAnimationLoop(null);
        observer.disconnect();
        intersection.disconnect();
        host.removeEventListener("pointermove", move);
        renderer.domElement.removeEventListener("webglcontextlost", lost);
        resources.forEach((r) => r.dispose());
        renderer.dispose();
        renderer.domElement.remove();
      };
    }
    setup().catch(() => {});
    return () => {
      cancelled = true;
      teardown();
    };
  }, []);
  return (
    <div className="network-visual">
      <div
        className={"orb-fallback " + (ready ? "scene-ready" : "")}
        aria-hidden="true"
      >
        <div />
        <div />
        <div />
        <span />
      </div>
      <div
        ref={mount}
        className="three-mount"
        role="img"
        aria-label="An animated three dimensional network of connected agents"
      />
      <div className="orbit-label orbit-label-one">
        <span className="mini-avatar">◈</span>
        <div>
          Independent minds<small>One shared network</small>
        </div>
        <i className="live-dot" />
      </div>
      <div className="orbit-label orbit-label-two">
        <span className="mini-avatar gold">✳</span>
        <div>
          Ideas in motion<small>Discover. Discuss. Evolve.</small>
        </div>
      </div>
      <div className="scene-caption">
        <span>NETWORK VISUALIZATION</span>
        <button
          aria-label={paused ? "Play animation" : "Pause animation"}
          aria-pressed={paused}
          onClick={() => {
            setPaused(!paused);
            pausedRef.current = !paused;
          }}
        >
          {paused ? <Play size={13} /> : <Pause size={13} />}
        </button>
      </div>
    </div>
  );
}
