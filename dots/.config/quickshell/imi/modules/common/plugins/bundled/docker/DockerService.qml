pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.plugins

Singleton {
    id: root

    readonly property string pluginId: "docker_plugin"
    readonly property string dockerBinary: PluginState.option(pluginId, "dockerBinary", "docker")
    readonly property string terminalApp: PluginState.option(pluginId, "terminalApp", "kitty")
    readonly property string shellPath: PluginState.option(pluginId, "shellPath", "/bin/sh")

    property bool dockerAvailable: false
    property bool refreshing: false
    property string lastError: ""
    property int totalCount: containers.length
    property int runningCount: containers.filter(container => container.isRunning).length
    property list<string> containerNames: containers.map(container => container.name)
    property var containers: []
    property var composeProjects: []

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function parseDockerPs(text) {
        const parsedContainers = [];
        for (const rawLine of text.split("\n")) {
            const line = rawLine.trim();
            if (!line) continue;
            try {
                const obj = JSON.parse(line);
                const id = obj.ID || obj.Id || "";
                const name = obj.Names || obj.Name || "";
                // A valid `docker ps --format '{{json .}}'` row always has
                // both fields. Ignore syntactically valid but incomplete JSON
                // rather than exposing a phantom unnamed container.
                if (!id || !name) continue;
                parsedContainers.push({
                    id: id,
                    name: name,
                    state: String(obj.State || "").toLowerCase(),
                    status: obj.Status || obj.State || "",
                    image: obj.Image || "",
                    isRunning: obj.State === "running" || obj.State === "Up"
                        || (obj.Status && obj.Status.startsWith("Up")),
                    isPaused: String(obj.Status || "").toLowerCase().includes("paused"),
                    ports: obj.Ports || "",
                    composeProject: obj.Labels?.["com.docker.compose.project"] || ""
                });
            } catch (error) {
                // Ignore incomplete event output and unsupported rows.
            }
        }
        return {
            totalCount: parsedContainers.length,
            runningCount: parsedContainers.filter(container => container.isRunning).length,
            containerNames: parsedContainers.map(container => container.name),
            containers: parsedContainers
        };
    }

    function parseInspect(text) {
        const raw = JSON.parse(text || "[]");
        if (!Array.isArray(raw)) return { containers: [], composeProjects: [] };

        const parsed = raw.map(container => {
            const labels = container.Config?.Labels || {};
            const bindings = container.NetworkSettings?.Ports || {};
            const ports = [];
            for (const containerPort in bindings) {
                for (const binding of bindings[containerPort] || []) {
                    if (!binding.HostPort) continue;
                    ports.push(`${binding.HostIp || "0.0.0.0"}:${binding.HostPort} → ${containerPort}`);
                }
            }
            const state = container.State?.Status || "unknown";
            return {
                id: container.Id || "",
                name: String(container.Name || "").replace(/^\//, ""),
                state: state,
                status: state.charAt(0).toUpperCase() + state.slice(1),
                image: container.Config?.Image || container.Image || "",
                isRunning: container.State?.Running === true,
                isPaused: container.State?.Paused === true,
                ports: ports,
                composeProject: labels["com.docker.compose.project"]
                    || labels["io.podman.compose.project"] || "",
                composeService: labels["com.docker.compose.service"]
                    || labels["io.podman.compose.service"] || "",
                composeWorkingDir: labels["com.docker.compose.project.working_dir"] || "",
                composeConfigFiles: labels["com.docker.compose.project.config_files"] || "compose.yaml",
                lastActivity: Math.max(
                    new Date(container.State?.StartedAt || 0).getTime(),
                    new Date(container.State?.FinishedAt || 0).getTime())
            };
        }).sort((a, b) => {
            const priority = state => state === "running" ? 0 : state === "paused" ? 1 : 2;
            return priority(a.state) - priority(b.state)
                || b.lastActivity - a.lastActivity
                || a.name.localeCompare(b.name);
        });

        const projectMap = {};
        for (const container of parsed) {
            if (!container.composeProject) continue;
            if (!projectMap[container.composeProject]) {
                projectMap[container.composeProject] = {
                    name: container.composeProject,
                    containers: [],
                    runningCount: 0,
                    totalCount: 0,
                    workingDir: container.composeWorkingDir,
                    configFile: container.composeConfigFiles
                };
            }
            const project = projectMap[container.composeProject];
            project.containers.push(container);
            project.totalCount++;
            if (container.isRunning) project.runningCount++;
        }
        const projects = Object.values(projectMap).sort((a, b) =>
            b.runningCount - a.runningCount || a.name.localeCompare(b.name));
        return { containers: parsed, composeProjects: projects };
    }

    function refresh() {
        if (refreshing) return;
        refreshing = true;
        availabilityProc.command = [dockerBinary, "info"];
        availabilityProc.running = true;
    }

    function fetchContainers() {
        inspectProc.command = ["bash", "-c",
            `${root.shellQuote(dockerBinary)} container inspect $(${root.shellQuote(dockerBinary)} container ls -aq)`];
        inspectProc.running = true;
    }

    function executeAction(containerId, action) {
        const allowed = ["start", "stop", "restart", "pause", "unpause"];
        if (!allowed.includes(action) || !containerId) return false;
        Quickshell.execDetached([dockerBinary, action, containerId]);
        actionRefresh.restart();
        return true;
    }

    function executeComposeAction(project, action) {
        const allowed = ["up", "down", "start", "stop", "restart", "pull"];
        if (!project?.workingDir || !allowed.includes(action)) return false;
        const args = [dockerBinary, "compose", "-f", project.configFile || "compose.yaml"];
        if (action === "up") args.push("up", "-d"); else args.push(action);
        const command = `cd ${root.shellQuote(project.workingDir)} && `
            + args.map(root.shellQuote).join(" ");
        Quickshell.execDetached(["bash", "-lc", command]);
        actionRefresh.restart();
        return true;
    }

    function terminalCommand(command) {
        if (terminalApp === "foot") return ["foot", "sh", "-lc", command];
        if (terminalApp === "alacritty") return ["alacritty", "-e", "sh", "-lc", command];
        return [terminalApp, "sh", "-lc", command];
    }

    function openLogs(containerId) {
        Quickshell.execDetached(root.terminalCommand(
            `${root.shellQuote(dockerBinary)} logs -f ${root.shellQuote(containerId)}`));
    }

    function openExec(containerId) {
        Quickshell.execDetached(root.terminalCommand(
            `${root.shellQuote(dockerBinary)} exec -it ${root.shellQuote(containerId)} ${root.shellQuote(shellPath)}`));
    }

    function openComposeLogs(project) {
        if (!project?.workingDir) return;
        const command = `cd ${root.shellQuote(project.workingDir)} && `
            + `${root.shellQuote(dockerBinary)} compose -f ${root.shellQuote(project.configFile || "compose.yaml")} logs -f`;
        Quickshell.execDetached(root.terminalCommand(command));
    }

    Process {
        id: availabilityProc
        onExited: (exitCode, exitStatus) => {
            root.dockerAvailable = exitCode === 0;
            if (root.dockerAvailable) root.fetchContainers();
            else {
                root.refreshing = false;
                root.containers = [];
                root.composeProjects = [];
                root.lastError = `${root.dockerBinary} is unavailable or inaccessible`;
            }
        }
    }

    Process {
        id: inspectProc
        stdout: StdioCollector { id: inspectOutput }
        onExited: (exitCode, exitStatus) => {
            root.refreshing = false;
            if (exitCode !== 0) {
                root.lastError = "Failed to inspect containers";
                return;
            }
            try {
                const result = root.parseInspect(inspectOutput.text);
                root.containers = result.containers;
                root.composeProjects = result.composeProjects;
                root.lastError = "";
            } catch (error) {
                root.lastError = "Invalid container data: " + error;
            }
        }
    }

    Timer { id: actionRefresh; interval: 800; onTriggered: root.refresh() }
    onDockerBinaryChanged: Qt.callLater(root.refresh)
    Component.onCompleted: root.refresh()
}
