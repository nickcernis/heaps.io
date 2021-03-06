package;

import data.Category;
import data.Page;
import haxe.Http;
import haxe.Json;
import haxe.ds.StringMap;
import haxe.io.Path;
import markdown.AST.ElementNode;
import sys.FileSystem;
import sys.io.File;
import templo.Template;

using StringTools;

/**
 * @author Mark Knol
 */
class Generator {
	public var contentPath = "./assets/content/";
	public var outputPath = "./output/";
	public var websiteRepositoryUrl = "";
	public var projectRepositoryUrl = "";
	public var repositoryBranch = "";
	public var basePath = "";
	public var titlePostFix = "";
	public var samplesFolder = "assets/includes/samples/"; 
	public var documentationFolder = "documentation/";
	public var assetsFolderName = "assets";
	
	private var _pages:Array<Page> = new Array<Page>();
	private var _folders:StringMap<Array<Page>> = new StringMap<Array<Page>>();
	private var _templates:StringMap<Template> = new StringMap<Template>();
	
	public function new() { }
	
	/**
	 * Build the website.
	 * @param doMinify minifies the HTML output.
	 */
	public function build (doMinify:Bool = false) {
		//deleteDirectory(outputPath);
		
		initTemplate();
		
		addDocumentationPages(documentationFolder);
		trace(_pages.length + " articles");
		
		addGeneralPages();
		
		// create list of categories (after all other pages are added)
		var sitemap:Array<Category> = createSitemap();
		
		// sort categories on name for display
		sitemap.sort(function(a, b) return a.title > b.title ? 1 : -1);
		
		// add overview page for each category
		addCategoryPages(sitemap);
		addSamplesPages(samplesFolder);
		
		// assign page.category
		for (page in _pages) page.category = getCategory(sitemap, page);
		
		// sort category pages by filename
		for (category in sitemap) category.pages.sort(function(a, b) {
			var a = a.outputPath.file;
			var b = b.outputPath.file;
			return if (a < b) -1;
				else if (a > b) 1;
				else 0;
		});
		
		
		var tags:StringMap<Array<Page>> = collectTags();
		// add tags to the home page (used for meta keywords)
		_pages[0].tags = [for (tag in tags.keys()) tag];
		//addTagPages(tags);

		// sort pages by date; get most recent pages
		var latestCreatedPages = [for (p in _pages) {
			if (p != null && p.category != null && p.visible && p.dates != null && p.dates.created != null) p;
		}];
		latestCreatedPages.sort(function(a, b) {
			var a = a.dates.created.getTime(), b = b.dates.created.getTime();
			return if (a > b) -1 else if (a < b) 1 else 0;
		});
		
		function isPage(page:Page, p:String):Bool return p.endsWith(page.outputPath.toString());
		
		for(page in _pages) {
			// set the data for the page
			trace(page.outputPath);
			var category = getCategory(sitemap, page);
			var data = {
				title: category != null ? '${page.title} - ${category.title} $titlePostFix' : '${page.title} $titlePostFix', 
				now: Date.now(),
				pages: _pages,
				currentPage: page,
				currentCategory: category,
				sitemap: sitemap,
				basePath: basePath,
				tags: tags,
				pageContent: null,
				DateTools: DateTools,
				websiteRepositoryUrl:websiteRepositoryUrl,
				projectRepositoryUrl:projectRepositoryUrl,
				isPage: isPage.bind(page),
				isCategory: if (category!=null) category.isCategory else function(_) return false,
				convertDate:function(date:Date) {
					// American date format is retarded: "Wed, 02 Oct 2002 13:00:00 GMT"
					var month = "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec".split(",")[date.getMonth()];
					var dayName = "Sun,Mon,Tue,Wed,Thu,Fri,Sat".split(",")[date.getDay()];
					var day = Std.string(date.getDate()).lpad("0", 2);
					var time = Std.string(date.getHours()).lpad("0", 2) + ":" + Std.string(date.getMinutes()).lpad("0", 2)	+ ":" + Std.string(date.getSeconds()).lpad("0", 2);
					return '$dayName, $day $month ${date.getFullYear()} $time GMT';
				},
				getSortedTags: getSortedTags.bind(tags),
				getTagTitle:getTagTitle,
				latestCreatedPages: function(amount) return [for (i in 0...min(amount, latestCreatedPages.length)) latestCreatedPages[i]],
			}
			if (page.contentPath != null) 
			{
				page.addLinkUrl = (category != null) ? getAddLinkUrl(category) : getAddLinkUrl(page);
				data.pageContent = page.pageContent != null ? page.pageContent : getContent(contentPath + page.contentPath, data);
			}
			
			// fix edit links category listing
			if (!page.visible && page.category != null)
			{ 
				page.contentPath = new Path(page.category.folder + "index.md");
				page.editUrl = getEditUrl(page);
			}
			
			// execute the template
			var templatePath = contentPath + page.templatePath;
			if (!_templates.exists(templatePath)) {
				_templates.set(templatePath, Template.fromFile(templatePath));
			}
			var template = _templates.get(templatePath);
			
			var html = util.Minifier.removeComments(template.execute(data));
			
			if (doMinify) {
				// strip crap
				var length = html.length;
				html = util.Minifier.minify(html);
				var newLength = html.length;
				//trace("optimized " + (Std.int(100 / length * (length - newLength) * 100) / 100) + "%");
			}
			
			// make output directory if needed
			var targetDirectory = Path.directory(outputPath + page.outputPath);
			if (!FileSystem.exists(targetDirectory)) {
				FileSystem.createDirectory(targetDirectory);
			}
			
			// write output to file
			File.saveContent(outputPath + page.outputPath, html);
		}
		
		var allTags = [for (tag in tags.keys()) tag];
		//File.saveContent("used-tags.txt", allTags.join("\r\n"));
		
		trace(sitemap.length + " categories");
		trace(allTags.length + " tags");
		trace(_pages.length + " pages done!");
	}

	private function addPage(page:Page, folder:String = null) {
		_pages.push(page);
		
		page.absoluteUrl = getAbsoluteUrl(page);
		page.baseHref = getBaseHref(page);
		
		if (page.contentPath != null) {
			page.dates = util.GitUtil.getStat(contentPath + page.contentPath);
			page.contributionUrl = getContributionUrl(page);
			page.editUrl = getEditUrl(page);
		}
		
		if (folder != null) {
			if (!_folders.exists(folder)) {
				_folders.set(folder, []);
			}
			_folders.get(folder).push(page);
		}
	}
	
	private function addCategoryPages(sitemap:Array<Category>) {
		for (category in sitemap) {
			var page =  new Page("layout-page-documentation.mtt", "table-of-content-category.mtt", 'documentation/${category.id}/index.html')
							.setTitle('${category.title}')
							.hidden();
			
			category.content = parseMarkdownContent(page, contentPath + category.folder + "index.md");
			addPage(page, category.folder);
			
		}
		
		var documentationLandingPage = new Page("layout-page-documentation.mtt",  documentationFolder + "index.md", 'documentation/index.html')
										.setTitle('Online handbook')
										.setDescription("Learn about Heaps.io")
										.hidden();
		addPage(documentationLandingPage, "documentation");
	}
	
	public static function deleteDirectory(path:String):Void {
		if (FileSystem.exists(path)) {
			for (file in FileSystem.readDirectory(path)) {
				var curPath = path + "/" + file;
				if (FileSystem.isDirectory(curPath)) { 
					deleteDirectory(curPath);
				} else { 
					FileSystem.deleteFile(curPath);
				}
			}
			FileSystem.deleteDirectory(path);
		}
	}
	
	private function addTagPages(tags:StringMap<Array<Page>>) {
		for (tag in tags.keys()) {
			var tagTitle = getTagTitle(tag);
			addPage(new Page("layout-page-toc.mtt",	"tags.mtt", 'tag/$tag.html')
												.setTitle('Heaps $tagTitle articles overview')
												.setCustomData({tag:tag, pages: tags.get(tag)})
												.setDescription('Overview of Haxe snippets and tutorials tagged with $tagTitle.')
												.hidden(), "tags");
		}
	}
	
	private function addGeneralPages() {
		var homePage = new Page("layout-page-main.mtt", "index.mtt", "index.html")
													.hidden()
													.setTitle("Heaps - Haxe Game Engine")
													.setDescription('Cross platform graphics for high performance games.');
		
		var json:{ web:Array<GameDef>, steam:Array<GameDef>} = Json.parse(File.getContent("assets/content/showcase/showcase.json"));
		var aboutPage = new Page("layout-page.mtt", "about.mtt", "about.html")
													.hidden()
													.setCustomData({
														games: json
													})
													.setTitle("About - Haxe game enine")
													.setDescription('Heaps.io delivers fast iterations, real development power and multi-platform compilation with native access and minimal overhead. The toolkit is versatile, open-source and completely free.');
		
		var errorPage = new Page("layout-page-main.mtt", "404.mtt", "404.html")
													.hidden()
													.setTitle("Page not found");
													
		var sitemapPage = new Page("sitemap.mtt", null, "sitemap.xml")
													.hidden()
													.setTitle("Sitemap");
		addPage(homePage, "/home");
		addPage(aboutPage, "/about");
		addPage(errorPage, "/404");
		
		errorPage.baseHref = "/";
	}
	
	private function addDocumentationPages(documentationPath:String, level:Int = 0) {
		for (file in FileSystem.readDirectory(contentPath + documentationPath)) {
			var outputPathReplace = 'documentation/';
			if (file.startsWith("index.")) continue; // skip this index page, its used for landingspages 
			if (!FileSystem.isDirectory(contentPath + documentationPath + file)) {
				var pageOutputPath = documentationPath.replace(documentationFolder, outputPathReplace);
				pageOutputPath = pageOutputPath.toLowerCase().replace(" ", "-") + getWithoutExtension(file).toLowerCase() + ".html";
				var page = new Page("layout-page-documentation.mtt",	documentationPath + file, pageOutputPath);
				page.level = level;
				page.pageContent = parseMarkdownContent(page, contentPath + documentationPath + file);
				addPage(page, documentationPath);
			} else {
				if (file == assetsFolderName) {
					// when assets folder name is found, dont recurse but include directory in output
					includeDirectory(contentPath + documentationPath + file, outputPath + documentationPath.replace(documentationFolder, outputPathReplace).toLowerCase().replace(" ", "-") + file);
				} else {
					// recursive
					addDocumentationPages(documentationPath + file + "/", level+1);
				}
			}
		}
	}
	
	private function addSamplesPages(samplesPath:String) {
		var prev:Page = null;
		var samples:Array<Page> = [];
		
		trace(contentPath + "samples/samples.json");
		var data:{ samples:Array<{ name:String, description:String}> } = Json.parse(File.getContent(contentPath + "samples/samples.json"));
		
		for (sample in data.samples) {
			var outFolder = 'samples/';
			var sampleName = sample.name;
			var sampleFolderName = sampleName.substr(0, 1).toLowerCase() + sampleName.substr(1); // starts with lowercase
			var pageOutputPath = sampleName.toLowerCase().replace(" ", "-").toLowerCase() + ".html";
			trace(samplesPath + sampleName + ".hx");
			var page = new Page("layout-page-samples.mtt", samplesPath + sampleName, '$outFolder$pageOutputPath')
				.setTitle(sampleName)
				.setDescription('Heaps $sampleName example with source and live demo')
				.setCustomData({
					source: getContent(samplesPath + sampleName + ".hx", null).replace("\t", "  ").replace("<", "&lt;").replace(">","&gt;"),
					file: '$outFolder' + sampleFolderName + "/",
					prev: prev,
					samples: samples,
				});
			var markdown  = new Markdown.Document();
			page.pageContent =  Markdown.renderHtml(markdown.parseInline(sample.description)); 
			if (prev != null) prev.customData.next = page;
			
			addPage(page, 'samples');
			samples.push(page);
			prev = page;
		}
		
		var page = new Page("layout-page.mtt", "samples.mtt", "samples/index.html")
			.setTitle("Examples overviews")
			.setDescription('Heaps examples overview with source and live demo')
			.setCustomData({samples:data})
			.hidden();
		addPage(page, 'samples');
	}

	private function getSortedTags(a:StringMap<Array<Page>>) {
		var keys = [for(key in a.keys()) {tag:key, total:a.get(key).length}];
		keys.sort(function(a, b) return a.total == b.total ? 0 :(a.total > b.total ? -1 : 1));
		return [for (key in keys) key.tag];
	}

	private function getTagTitle(tag:String):String {
		return tag.replace("-", " ");
	}

	// categorizes the folders 
	private function createSitemap():Array<Category> {
		var sitemap = [];
		for (key in _folders.keys()) {
			var structure = key.split("/");
			structure.pop();
			if (key.indexOf(documentationFolder) == 0) {
				var id = structure.pop();
				var categoryId = id;
				categoryId = categoryId.toLowerCase().replace(" ", "-");
				var category = new Category(categoryId, id.replace("-", " "), key, _folders.get(key));
				category.absoluteUrl = basePath + category.outputPath;
				sitemap.push(category);
			}
		}
		return sitemap;
	}
	
	// collects all tags and counts them
	private function collectTags() {
		var tags = new StringMap<Array<Page>>();
		for (page in _pages) {
			if (page.tags != null) {
				for (tag in page.tags) {
					tag = tag.toLowerCase();
					if (!tags.exists(tag)) {
						tags.set(tag, []);
					}
					tags.get(tag).push(page);
				}
			}
		}
		return tags;
	}
	
	private function replaceTryHaxeTags(content:String) {
		//[tryhaxe](http://try.haxe.org/embed/ae6ef)
		return	~/(\[tryhaxe\])(\()(.+?)(\))/g.replace(content, '<iframe src="$3" class="try-haxe"><a href="$3">Try Haxe!</a></iframe>');
	}
	
	private function replaceYoutubeTags(content:String) {
		//[youtube](https://www.youtube.com/watch?v=dQw4w9WgXcQ)
		return	~/(\[youtube\])(\()(.+?)(\))/g.replace(content, '<div class="flex-video widescreen"><iframe src="$3" frameborder="0" allowfullscreen=""></iframe></div>');
	}
	
	private function replaceHaxeOrgLinks(content:String) 
	{
		return content.split("http://haxe.org").join("https://haxe.org");
	}
	
	private function replaceAuthor(content:String) {
		//Author: [name](url) / [name](url) 
		if (content.indexOf("Author:") != -1) {
			var authorLineOld = content.split("Author:").pop().split("\n").shift();
			var authorline = ~/\[(.*?)\]\((.+?)\)/g.replace(authorLineOld, '<a href="$2" itemprop="url" rel="external"><span itemprop="name">$1</span></a>');
			authorline = '<span itemprop="author" itemscope="itemscope" itemtype="https://schema.org/Person">$authorline</span>';
			return	content.replace(authorLineOld, authorline);
		} else {
			return content;
		}
	}
	
	private function getCategory(sitemap:Array<Category>, page:Page):Category {
		for (category in sitemap) {
			if (category.pages.indexOf(page) != -1 ) {
				return category;
			}
		}
		return null;
	}
	
	private function getCategoryById(sitemap:Array<Category>, id:String):Category {
		for (category in sitemap) {
			if (category.id == id) {
				return category;
			}
		}
		return null;
	}
	
	private function getBaseHref(page:Page) {
		if (page.outputPath.file == "404.html") {
			return basePath;
		}
		var href = [for (s in page.outputPath.toString().split("/")) ".."];
		href[0] = ".";
		return href.join("/");
	}
	
	public inline function getEditUrl(page:Page) {
		return '${websiteRepositoryUrl}edit/${repositoryBranch}/${contentPath}${page.contentPath}';
	}
	
	public inline function getContributionUrl(page:Page) {
		return '${websiteRepositoryUrl}tree/${repositoryBranch}/${contentPath}${page.contentPath}';
	}
	
	public function getAddLinkUrl(category:Category = null, page:Page = null) {
		var fileNameHint = "/page-name.md/?filename=page-name.md";
		var directory = if (category != null) {
			category.pages[0].contentPath.dir;
		} else {
			page.contentPath.dir;
		}
		return '${websiteRepositoryUrl}new/master/${contentPath}${directory}${fileNameHint}';
	}
	
	public inline function getAbsoluteUrl(page:Page) {
		return basePath + page.outputPath.toString();
	}
	
	private static inline function getWithoutExtension(file:String) {
		return Path.withoutDirectory(Path.withoutExtension(file));
	}
	
	private function getContent(file:String, data:Dynamic) {
		return switch(Path.extension(file)) {
			case "md": 
				parseMarkdownContent(null, file);
			case "mtt": 
				Template.fromFile(file).execute(data);
			default: 
				File.getContent(file);
		}
	}
	
	public function parseMarkdownContent(page:Page, file:String):String {
		var document = new Markdown.Document();
		var markdown = File.getContent(file);
		markdown = replaceHaxeOrgLinks(markdown);
		markdown = replaceYoutubeTags(markdown);
		markdown = replaceTryHaxeTags(markdown);
		markdown = replaceAuthor(markdown);
		
		try {
			// replace windows line endings with unix, and split
			var lines = ~/(\r\n|\r)/g.replace(markdown, '\n').split("\n");
			
			// parse ref links
			document.parseRefLinks(lines);
			
			// parse tags
			if (page != null) {
				var link = document.refLinks["tags"];
				page.tags = link != null ? [for (a in link.title.split(",")) a.toLowerCase().trim()] : null;
			}
			
			// parse ast
			var blocks = document.parseLines(lines);
			// pick first header, use it as title for the page
			var titleBlock = null;
			if (page != null) {
				var hasTitle = false;
				for (block in blocks) {
					var el = Std.instance(block, ElementNode);
					if (el != null) {
						if (!hasTitle && el.tag == "h1" && !el.isEmpty()) {
							page.title = new markdown.HtmlRenderer().render(el.children);
							hasTitle = true;
							titleBlock = block;
							continue;
						}
						if (hasTitle && el.tag != "pre" && page.description == null) {
							var description = new markdown.HtmlRenderer().render(el.children);
							page.description = new EReg("<(.*?)>", "g").replace(description, "").replace('"', "").replace('\n', " ");
							break;
						}
					}
				}
			}
			if (titleBlock != null) blocks.remove(titleBlock);

			return Markdown.renderHtml(blocks);
		} catch (e:Dynamic){
			return '<pre>$e</pre>';
		}
	}
	
	public function includeDirectory(dir:String, ?path:String) {
		if (path == null) path = outputPath;
		else FileSystem.createDirectory(path);
		trace("include directory: " + path);
		
		for (file in FileSystem.readDirectory(dir)) {
			var srcPath = '$dir/$file';
			var dstPath = '$path/$file';
			if (FileSystem.isDirectory(srcPath)) {
				FileSystem.createDirectory(dstPath);
				includeDirectory(srcPath, dstPath);
			} else {
				if (FileSystem.exists(dstPath)) {
					var statFrom = FileSystem.stat(srcPath);
					var statTo = FileSystem.stat(dstPath);
					if (statFrom.mtime.getTime() < statTo.mtime.getTime()) {
						// only copy files with newer modified time
						continue;
					}
				}
				File.copy(srcPath, dstPath);
			}
		}
	}
	
	private function initTemplate() {
		// for some reason this is needed, otherwise templates doesn't work.
		// the function fails, but i think internally Template can resolve paths now.
		try { 
			Template.fromFile(contentPath + "layout-main.mtt").execute({});
		} catch (e:Dynamic) { }
	}
	
	static inline private function min(a:Int, b:Int) return Std.int(Math.min(a, b));
}
typedef GameDef = { image: String, title: String, author:String, url: String }
