const Docker = require('dockerode');
const simpleGit = require('simple-git');
const fs = require('fs').promises;
const path = require('path');
const yaml = require('js-yaml');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);
const docker = new Docker();

const WORKSPACES_BASE_DIR = '/home';
const NGINX_CONFIG_DIR = '/opt/nginx-config';

async function createWorkspace(username, workspaceName, repoUrl, envVars = {}) {
  const workspaceDir = path.join(WORKSPACES_BASE_DIR, username, 'workspaces', workspaceName);
  
  // Create workspace directory
  await fs.mkdir(workspaceDir, { recursive: true });
  
  // Clone repository
  const git = simpleGit();
  await git.clone(repoUrl, workspaceDir);
  
  // Check for devcontainer.json
  const devcontainerPath = path.join(workspaceDir, '.devcontainer', 'devcontainer.json');
  let devcontainer = null;
  
  try {
    const devcontainerContent = await fs.readFile(devcontainerPath, 'utf8');
    devcontainer = JSON.parse(devcontainerContent);
  } catch (error) {
    console.log('No devcontainer.json found, using default configuration');
  }
  
  // Create container
  const containerConfig = await buildContainerConfig(username, workspaceName, workspaceDir, devcontainer, envVars);
  const container = await docker.createContainer(containerConfig);
  
  // Start container
  await container.start();
  
  const containerInfo = await container.inspect();
  const containerPort = getCodeServerPort(containerInfo);
  
  // Update nginx configuration
  await updateNginxConfig(username, workspaceName, containerInfo.Id, containerPort);
  
  return {
    containerId: containerInfo.Id,
    name: workspaceName,
    url: `/${username}/workspaces/${workspaceName}`,
    status: 'running'
  };
}

async function buildContainerConfig(username, workspaceName, workspaceDir, devcontainer, envVars) {
  const containerName = `workspace-${username}-${workspaceName}`;
  
  // Default configuration
  let image = 'codercom/code-server:latest';
  let env = [
    `PASSWORD=${generatePassword()}`,
    'SUDO_PASSWORD=password',
    ...Object.entries(envVars).map(([key, value]) => `${key}=${value}`)
  ];
  
  // Use devcontainer configuration if available
  if (devcontainer) {
    if (devcontainer.image) {
      image = devcontainer.image;
    }
    if (devcontainer.build) {
      // Build custom image if needed
      // For simplicity, we'll use the base image
      console.log('Custom build not yet supported, using default image');
    }
  }
  
  return {
    name: containerName,
    Image: image,
    Env: env,
    ExposedPorts: {
      '8080/tcp': {}
    },
    HostConfig: {
      Binds: [
        `${workspaceDir}:/home/coder/workspace`,
      ],
      PortBindings: {
        '8080/tcp': [{ HostPort: '0' }] // Random port
      },
      AutoRemove: false,
      RestartPolicy: {
        Name: 'unless-stopped'
      }
    },
    Labels: {
      'pseudo-codespaces.username': username,
      'pseudo-codespaces.workspace': workspaceName
    }
  };
}

function getCodeServerPort(containerInfo) {
  const ports = containerInfo.NetworkSettings.Ports;
  if (ports['8080/tcp'] && ports['8080/tcp'].length > 0) {
    return ports['8080/tcp'][0].HostPort;
  }
  throw new Error('Could not determine code-server port');
}

async function updateNginxConfig(username, workspaceName, containerId, port) {
  const configFile = path.join(NGINX_CONFIG_DIR, `workspace-${username}-${workspaceName}.conf`);
  
  const config = `
# Workspace: ${username}/${workspaceName}
location /${username}/workspaces/${workspaceName}/ {
    proxy_pass http://localhost:${port}/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 86400;
}
`;
  
  await fs.writeFile(configFile, config);
  
  // Reload nginx
  await execAsync('docker exec nginx nginx -s reload');
}

async function deleteWorkspace(containerId) {
  try {
    const container = docker.getContainer(containerId);
    
    // Stop container
    try {
      await container.stop();
    } catch (error) {
      console.log('Container already stopped');
    }
    
    // Remove container
    await container.remove();
    
    // Get container info to remove nginx config
    const containerInfo = await container.inspect().catch(() => null);
    if (containerInfo) {
      const username = containerInfo.Config.Labels['pseudo-codespaces.username'];
      const workspaceName = containerInfo.Config.Labels['pseudo-codespaces.workspace'];
      
      // Remove nginx config
      const configFile = path.join(NGINX_CONFIG_DIR, `workspace-${username}-${workspaceName}.conf`);
      await fs.unlink(configFile).catch(() => {});
      
      // Reload nginx
      await execAsync('docker exec nginx nginx -s reload');
    }
  } catch (error) {
    console.error('Error deleting workspace:', error);
    throw error;
  }
}

async function startWorkspace(containerId) {
  const container = docker.getContainer(containerId);
  await container.start();
}

async function stopWorkspace(containerId) {
  const container = docker.getContainer(containerId);
  await container.stop();
}

function generatePassword() {
  return Math.random().toString(36).slice(-12);
}

module.exports = {
  createWorkspace,
  deleteWorkspace,
  startWorkspace,
  stopWorkspace
};
