import simpleGit, { StatusResult, SimpleGit } from "simple-git";
import dotenv from "dotenv";
const exec = require("child_process").exec;
import fs from "fs";
import pjson from "../package.json";

dotenv.config();

const path_SC_root = "./";
const path_SC_ABI = "struct-core-abi";
const branch_SC_ABI = "develop";
const path_build = "build";
const path_typechain = "typechain-types";
const path_broadcast_AVAX = "broadcast/Deploy.s.sol/43114/";

async function pushABI(workingDir: string) {
    const nameGH = process.env.GITHUB_NAME;
    const emailGH = process.env.GITHUB_EMAIL;
    const tokenGH = process.env.GITHUB_TOKEN;
    if (!nameGH || !emailGH || !tokenGH) {
        throw new Error("Missing environment variables necessary for commit. Exiting process.");
    }
    const gitSC = simpleGit(workingDir);
    try {
        await gitSC.addConfig("user.name", nameGH);
        await gitSC.addConfig("user.email", emailGH);
        const abiRepoUrl = `https://${nameGH}:${tokenGH}@github.com/struct-defi/struct-core-abi.git`;

        const gitSC_ABI = await copyFilesToABIRepo(gitSC, abiRepoUrl);
        try {
            const statusSummary = await gitSC_ABI.status();
            const commitResult = await checkAndCommitChanges(gitSC_ABI, statusSummary);
            if (commitResult) console.log("commit summary: ", commitResult.summary);
        } catch (err) {
            throw new Error("Error committing files to remote struct-core-abi:" + err);
        }

        try {
            const versionLatest = pjson.version;
            await gitSC_ABI.addTag(versionLatest);
        } catch (err) {
            throw new Error("Error tagging head of branch: " + err);
        }

        try {
            await gitSC_ABI.push(abiRepoUrl, branch_SC_ABI, ["--tags"]);
            console.log("pushed changes to struct-core-abi repo");
        } catch (err) {
            throw new Error("Error pushing files to remote struct-core-abi:" + err);
        }
    } catch (err) {
        throw new Error(err);
    }
}

async function copyFilesToABIRepo(git: SimpleGit, repoURL: string) {
    try {
        console.log(`cloning struct-core-abi repo...`);
        await git.clone(repoURL, ["-b", branch_SC_ABI]);
    } catch (err) {
        throw new Error(`Error cloning ${path_SC_ABI} repo:` + err);
    }
    const gitSC_ABI = simpleGit(`./${path_SC_ABI}`);
    await removeDeletedFilesFromRepo(gitSC_ABI);
    try {
        await gitSC_ABI.push(repoURL);
    } catch (err) {
        throw new Error("Error pushing deleted file commits: " + err);
    }

    console.log(`copying ./${path_build} directory to ${path_SC_ABI}`);
    await execShellCommand(`cp -R ./${path_build} ./${path_SC_ABI}/`);

    console.log(`copying ./${path_typechain} directory to ${path_SC_ABI}`);
    await execShellCommand(`cp -R ./${path_typechain} ./${path_SC_ABI}/`);

    console.log(`copying ./${path_broadcast_AVAX} file to ${path_SC_ABI}`);
    await execShellCommand(`cp -R ./${path_broadcast_AVAX} ./${path_SC_ABI}/`);

    return gitSC_ABI;
}

async function generateDeletedFilePaths(folderName: string) {
    // check if directory exists
    if (fs.existsSync(`${path_SC_ABI}/${folderName}`)) {
        const diff: string = await execShellCommand(
            `diff -q --recursive ${folderName} ${path_SC_ABI}/${folderName}`
        );
        const messageArr = diff.split("\n");
        const deletedFileMessages = messageArr.filter((message) => {
            return message.includes(`Only in ${path_SC_ABI}`);
        });
        const deletedFilePaths = deletedFileMessages.map((message) => {
            const pathRaw = message.substr(message.indexOf("/") + 1);
            var path = pathRaw.replace(": ", "/");
            return path;
        });
        return deletedFilePaths;
    } else {
        console.log(`Directory ${path_SC_ABI}/${folderName} not found.`);
        return [];
    }
}

async function removeDeletedFilesFromRepo(gitSC_ABI: SimpleGit) {
    // get diff between ABI directories
    const deletedFilePathsArtifacts = await generateDeletedFilePaths(path_build);

    // get diff between typechain directories
    const deletedFilePathsTypechain = await generateDeletedFilePaths(path_typechain);
    const deletedFilePaths = [deletedFilePathsArtifacts, deletedFilePathsTypechain].flat();

    if (deletedFilePaths.length !== 0) {
        console.log(`deleting files from ${path_SC_ABI}/${path_build}: ${deletedFilePaths}`);
        for (const deletedFile of deletedFilePaths) {
            try {
                await gitSC_ABI.raw(["rm", "-r", deletedFile]);
            } catch (err) {
                throw new Error("error deleting file" + err);
            }
        }
        await gitSC_ABI.commit(
            `remove deleted files from ${path_build} or ${path_typechain} directory`
        );
    }
}

function execShellCommand(cmd): Promise<string> {
    return new Promise((resolve, reject) => {
        exec(cmd, (error, stdout, stderr) => {
            if (error) {
                console.warn(error);
            }
            resolve(stdout ? stdout : stderr);
        });
    });
}

async function checkAndCommitChanges(git: SimpleGit, statusSummary: StatusResult) {
    const fileNamesAndPaths = filterABIFiles(statusSummary);
    if (Object.keys(fileNamesAndPaths).length === 0) {
        console.log(`No change to ${path_build} directory.`);
        return;
    }
    try {
        await stageFiles(git, fileNamesAndPaths);
        const commitResults = await commitFiles(git, fileNamesAndPaths);
        return commitResults;
    } catch (err) {
        throw new Error("Error staging or committing files" + err);
    }
}

function filterABIFiles(statusSummary: StatusResult) {
    const fileNameAndPath: Record<string, string[]> = {};
    Object.entries(statusSummary).forEach(([key, value]) => {
        enum ChangeTypes {
            "not_added" = "added",
            created = "created",
            deleted = "deleted",
            modified = "modified",
            renamed = "renamed",
        }
        if (ChangeTypes[key] && value.length !== 0) {
            const fileABIsAndTypeChain = value.filter((file) => {
                let dirName = file.split("/")[1];

                return (
                    (dirName && !dirName.endsWith(".t.sol") && !dirName.endsWith(".s.sol")) ||
                    file.includes("typechain-types") ||
                    file.includes("versionHistory") ||
                    file.includes("run-latest")
                );
            });
            Object.assign(fileNameAndPath, { [ChangeTypes[key]]: fileABIsAndTypeChain });
        }
    });
    if (Object.keys(fileNameAndPath).length !== 0) {
        console.log(`preparing to commit ${Object.keys(fileNameAndPath).length} files`);
        return fileNameAndPath;
    } else {
        return {};
    }
}

async function stageFiles(git: SimpleGit, fileNameAndPath: Record<string, string[]>) {
    const allFilesToStage: string[] = [];
    Object.values(fileNameAndPath).map((paths) => {
        allFilesToStage.push(...paths);
    });
    const stageResult = await git.add(allFilesToStage);
    return stageResult;
}

async function commitFiles(git: SimpleGit, fileNameAndPath: Record<string, string[]>) {
    let commitMsg = "change set: ";
    Object.entries(fileNameAndPath).forEach(([key, value]) => {
        value.forEach((file: string) => {
            commitMsg += `${key} file ${file}; \n`;
        });
    });
    // Commit changes
    console.log("Commit message: ", commitMsg);
    const commitResult = await git.commit(commitMsg);
    return commitResult;
}

pushABI(path_SC_root);
