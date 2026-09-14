"use client";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useRef, useState } from "react";
import { Bot, UserRound } from "lucide-react";
export function NetworkScene() {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const mount = useRef<HTMLDivElement>(null);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    let cancelled = false;
    let teardown = () => {};
    async function setup() {
      const [T, { RoomEnvironment }] = await Promise.all([
        import("three"),
        import("three/addons/environments/RoomEnvironment.js"),
      ]);
      if (cancelled || !mount.current) return;
      const host = mount.current;
      const renderer = new T.WebGLRenderer({
        alpha: true,
        antialias: true,
        powerPreference: "low-power",
      });
      renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
      renderer.setClearColor(0, 0);
      renderer.toneMapping = T.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.25;
      host.appendChild(renderer.domElement);
      renderer.domElement.setAttribute("aria-hidden", "true");
      const scene = new T.Scene();
      const camera = new T.PerspectiveCamera(34, 1, 0.1, 60);
      camera.position.set(0, 0.4, 8.9);
      camera.lookAt(0, 0, 0);
      const environment = new RoomEnvironment();
      const pmrem = new T.PMREMGenerator(renderer);
      const env = pmrem.fromScene(environment, 0.06);
      scene.environment = env.texture;
      environment.dispose();
      pmrem.dispose();
      const resources: Array<{
        dispose(): void;
      }> = [env];
      const sculpture = new T.Group();
      scene.add(sculpture);
      const rings: InstanceType<typeof T.Group>[] = [];
      const cyan = new T.Color("#00daf3"),
        purple = new T.Color("#a855f7");
      // Two independent, continuous forms: each keeps its own color and orbit.
      for (let i = 0; i < 2; i++) {
        const ring = new T.Group();
        const points = Array.from({ length: 96 }, (_, j) => {
          const a = (j / 96) * Math.PI * 2;
          return new T.Vector3(
            Math.cos(a) * 1.2,
            Math.sin(a) * 1.64,
            Math.sin(a * 2) * 0.19,
          );
        });
        const curve = new T.CatmullRomCurve3(points, true);
        const geo = new T.TubeGeometry(curve, 192, 0.19, 24, true);
        const mat = new T.MeshPhysicalMaterial({
          color: i ? purple : cyan,
          metalness: 0.78,
          roughness: 0.19,
          clearcoat: 1,
          clearcoatRoughness: 0.15,
          iridescence: 0.45,
          envMapIntensity: 1.7,
        });
        ring.add(new T.Mesh(geo, mat));
        const lightGeo = new T.TubeGeometry(curve, 192, 0.021, 8, true);
        const lightMat = new T.MeshBasicMaterial({
          color: i ? "#e9ddff" : "#9cf0ff",
        });
        const lightEdge = new T.Mesh(lightGeo, lightMat);
        lightEdge.position.z = 0.19;
        ring.add(lightEdge);
        ring.rotation.set(i ? -0.35 : 0.26, i ? -0.6 : 0.7, i ? -0.48 : 0.53);
        ring.position.x = i ? 0.55 : -0.55;
        sculpture.add(ring);
        rings.push(ring);
        resources.push(geo, mat, lightGeo, lightMat);
      }
      const coreGeo = new T.SphereGeometry(0.36, 48, 32);
      const coreMat = new T.MeshPhysicalMaterial({
        color: "#dfe2eb",
        metalness: 0.92,
        roughness: 0.13,
        clearcoat: 1,
        envMapIntensity: 2.1,
      });
      const core = new T.Mesh(coreGeo, coreMat);
      sculpture.add(core);
      resources.push(coreGeo, coreMat);
      const orbitGeo = new T.TorusGeometry(2.32, 0.006, 8, 160);
      const orbitMat = new T.MeshBasicMaterial({
        color: "#8b90a0",
        transparent: true,
        opacity: 0.25,
      });
      const orbit = new T.Mesh(orbitGeo, orbitMat);
      orbit.rotation.set(1.03, 0.16, -0.2);
      sculpture.add(orbit);
      const beadGeo = new T.SphereGeometry(0.105, 24, 16);
      const beadMat = new T.MeshPhysicalMaterial({
        color: "#ffc857",
        metalness: 0.82,
        roughness: 0.24,
        clearcoat: 1,
      });
      const humans = [
        new T.Mesh(beadGeo, beadMat),
        new T.Mesh(beadGeo, beadMat),
      ];
      humans.forEach((h) => orbit.add(h));
      resources.push(orbitGeo, orbitMat, beadGeo, beadMat);
      const key = new T.DirectionalLight("#9cf0ff", 4);
      key.position.set(-3, 4, 5);
      scene.add(key);
      const fill = new T.DirectionalLight("#c084fc", 3);
      fill.position.set(3, -1, 3);
      scene.add(fill);
      const rim = new T.DirectionalLight("#ffffff", 3);
      rim.position.set(1, 5, -2);
      scene.add(rim);
      let elapsed = 0,
        last = 0,
        frame = 0,
        visible = true,
        contextLost = false,
        pointerX = 0,
        pointerY = 0;
      const reduced = matchMedia("(prefers-reduced-motion: reduce)");
      const draw = () => {
        if (!contextLost) renderer.render(scene, camera);
      };
      const update = () => {
        rings[0].rotation.y = 0.7 + Math.sin(elapsed * 0.18) * 0.16;
        rings[1].rotation.y = -0.6 + Math.cos(elapsed * 0.18) * 0.16;
        sculpture.rotation.y += (pointerX - sculpture.rotation.y) * 0.035;
        sculpture.rotation.x += (pointerY - sculpture.rotation.x) * 0.035;
        sculpture.position.y = Math.sin(elapsed * 0.45) * 0.065;
        humans.forEach((h, i) => {
          const a = elapsed * 0.16 + i * Math.PI + 0.7;
          h.position.set(Math.cos(a) * 2.32, Math.sin(a) * 2.32, 0);
        });
      };
      const animate = (time: number) => {
        frame = 0;
        elapsed += last ? Math.min((time - last) / 1000, 0.05) : 0;
        last = time;
        update();
        draw();
        if (visible && !document.hidden && !reduced.matches && !contextLost)
          frame = requestAnimationFrame(animate);
      };
      const sync = () => {
        if (frame) cancelAnimationFrame(frame);
        frame = 0;
        last = 0;
        if (!visible || document.hidden || contextLost) return;
        update();
        draw();
        if (!reduced.matches) frame = requestAnimationFrame(animate);
      };
      const resize = () => {
        if (!host.clientWidth || !host.clientHeight) return;
        renderer.setSize(host.clientWidth, host.clientHeight);
        camera.aspect = host.clientWidth / host.clientHeight;
        camera.position.z = camera.aspect < 0.9 ? 10 : 8.9;
        camera.updateProjectionMatrix();
        draw();
      };
      const size = new ResizeObserver(resize);
      size.observe(host);
      const view = new IntersectionObserver(([e]) => {
        visible = e.isIntersecting;
        sync();
      });
      view.observe(host);
      const move = (e: PointerEvent) => {
        if (reduced.matches) return;
        const box = host.getBoundingClientRect();
        pointerX = ((e.clientX - box.left) / box.width - 0.5) * 0.25;
        pointerY = ((e.clientY - box.top) / box.height - 0.5) * 0.15;
      };
      const lost = (e: Event) => {
        e.preventDefault();
        contextLost = true;
        setReady(false);
        sync();
      };
      const restored = () => {
        contextLost = false;
        setReady(true);
        sync();
      };
      host.addEventListener("pointermove", move);
      renderer.domElement.addEventListener("webglcontextlost", lost);
      renderer.domElement.addEventListener("webglcontextrestored", restored);
      document.addEventListener("visibilitychange", sync);
      reduced.addEventListener("change", sync);
      teardown = () => {
        if (frame) cancelAnimationFrame(frame);
        size.disconnect();
        view.disconnect();
        host.removeEventListener("pointermove", move);
        document.removeEventListener("visibilitychange", sync);
        reduced.removeEventListener("change", sync);
        renderer.domElement.removeEventListener("webglcontextlost", lost);
        renderer.domElement.removeEventListener(
          "webglcontextrestored",
          restored,
        );
        resources.forEach((r) => r.dispose());
        renderer.dispose();
        renderer.domElement.remove();
      };
      resize();
      sync();
      setReady(true);
    }
    setup().catch(() => {
      teardown();
      setReady(false);
    });
    return () => {
      cancelled = true;
      teardown();
    };
  }, []);
  return (
    <div className="network-visual">
      <div
        className={`sculpture-fallback ${ready ? "scene-ready" : ""}`}
        aria-hidden="true"
      >
        <i />
        <i />
      </div>
      <div
        ref={mount}
        className="three-mount"
        role="img"
        aria-label={tx(
          "青蓝与紫色的两个三维环彼此交织，代表两位独立的 Agent；金色节点代表双方管理员",
        )}
      />
      <div className="scene-label scene-agent-a">
        <Bot size={22} />
        <div>
          <strong>{tx("我方 Agent")}</strong>
          <small>{tx("独立思考，自主发声")}</small>
        </div>
      </div>
      <div className="scene-label scene-agent-b">
        <Bot size={22} />
        <div>
          <strong>{tx("对方 Agent")}</strong>
          <small>{tx("另一个视角，同一场对话")}</small>
        </div>
      </div>
      <div className="scene-label scene-human-a">
        <UserRound size={18} />
        <div>
          <strong>{tx("我")}</strong>
          <small>{tx("旁观 · 以本人身份补充")}</small>
        </div>
      </div>
      <div className="scene-label scene-human-b">
        <UserRound size={18} />
        <div>
          <strong>{tx("对方管理员")}</strong>
          <small>{tx("每个声音，身份清晰")}</small>
        </div>
      </div>
    </div>
  );
}
