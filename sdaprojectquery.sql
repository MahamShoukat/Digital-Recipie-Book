create database sdaproj
CREATE TABLE Users ( Id INT PRIMARY KEY IDENTITY(1,1),FullName varchar(50) not null, Username VARCHAR(50) NOT NULL,Password VARCHAR(50) NOT NULL,email varchar(50) not null,skills varchar(10)
);

CREATE TABLE Badges ( BadgeId INT PRIMARY KEY ,UserId INT UNIQUE,Bronze int not null, Gold int NOT NULL,Silver int NOT NULL,FOREIGN KEY (UserId) REFERENCES Users(Id));

CREATE TABLE Recipes (
    RecipeId INT PRIMARY KEY IDENTITY(1,1),
    UserId INT NOT NULL,
    RecipeName VARCHAR(100) NOT NULL,
    CategoryId INT,
    Ingredients VARCHAR(MAX) NOT NULL,
    StepsToCook VARCHAR(MAX) NOT NULL,
    DateCreated DATETIME NOT NULL DEFAULT GETDATE(), -- auto-sets current date/time
    FOREIGN KEY (UserId) REFERENCES Users(Id),FOREIGN KEY (CategoryId)
REFERENCES Category(CategoryId)
);

CREATE TABLE Category (
    CategoryId INT PRIMARY KEY IDENTITY(1,1),
    CategoryName VARCHAR(50) NOT NULL
);
CREATE TABLE Favourites (
    FavouriteId INT PRIMARY KEY IDENTITY(1,1),
    UserId INT NOT NULL,
    RecipeId INT NOT NULL,
    FOREIGN KEY (UserId) REFERENCES Users(Id),
    FOREIGN KEY (RecipeId) REFERENCES Recipes(RecipeId)
);
CREATE TABLE UserUpdateLog (
    LogId INT PRIMARY KEY IDENTITY(1,1),
    UserId INT,
    UpdatedColumn VARCHAR(50),
    OldValue VARCHAR(255),
    NewValue VARCHAR(255),
    UpdatedAt DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (UserId) REFERENCES Users(Id)
);

select * from Users
select * from Badges
select * from Recipes
select * from Favourites
select * from Category
select * from UserUpdateLog

ALTER TABLE Users ADD Points INT NOT NULL DEFAULT 0;

 INSERT INTO Category (CategoryName) VALUES ('Appetizer'),('Main Course'),('Dessert'), ('Beverages'),('Snacks'),('Salads'),('Soups'),('Breakfast');


 -----------Stored Prcedure for updating profile -----------------
CREATE PROCEDURE UpdateUserProfile
    @CurrentUsername VARCHAR(50),
    @ColumnName VARCHAR(50),
    @NewValue VARCHAR(255)
AS
BEGIN
    IF @ColumnName = 'username'
    BEGIN
        UPDATE Users SET username = @NewValue WHERE username = @CurrentUsername;
    END
    ELSE IF @ColumnName = 'fullname'
    BEGIN
        UPDATE Users SET fullname = @NewValue WHERE username = @CurrentUsername;
    END
    ELSE IF @ColumnName = 'email'
    BEGIN
        UPDATE Users SET email = @NewValue WHERE username = @CurrentUsername;
    END
    ELSE IF @ColumnName = 'password'
    BEGIN
        UPDATE Users SET password = @NewValue WHERE username = @CurrentUsername;
    END
    ELSE
    BEGIN
        RAISERROR('Invalid column name.', 16, 1);
    END
END;
------------ Stored procedure for updating skill ---------------
CREATE PROCEDURE UpdateUserSkillLevel
    @UserId INT
AS
BEGIN
    DECLARE @Bronze INT, @Silver INT, @Gold INT;
    DECLARE @NewSkill VARCHAR(50);

    -- Get badge counts
    SELECT @Bronze = Bronze, @Silver = Silver, @Gold = Gold
    FROM Badges
    WHERE UserId = @UserId;

    -- Determine skill level
    SET @NewSkill = 'Newbie';

    IF @Gold >= 5
        SET @NewSkill = 'Chef’s Level';
    ELSE IF @Silver >= 5
        SET @NewSkill = 'Pro';
    ELSE IF @Bronze >= 5
        SET @NewSkill = 'Home Cook';

    -- Update skill in Users table
    UPDATE Users
    SET Skills = @NewSkill
    WHERE Id = @UserId;
END

------ Stored Procedure for updating points and badges---------------------
CREATE PROCEDURE UpdateUserPointsAndBadges
    @UserId INT
AS
BEGIN
    -- Add 10 points
    UPDATE Users
    SET Points = Points + 10
    WHERE Id = @UserId;

    -- Get updated points
    DECLARE @Points INT;
    SELECT @Points = Points FROM Users WHERE Id = @UserId;

    -- Calculate badges
    DECLARE @Bronze INT = @Points / 50;
    DECLARE @Silver INT = @Points / 100;
    DECLARE @Gold INT = @Points / 200;

    -- Insert or update badges
    IF EXISTS (SELECT 1 FROM Badges WHERE UserId = @UserId)
    BEGIN
        UPDATE Badges
        SET Bronze = @Bronze,
            Silver = @Silver,
            Gold = @Gold
        WHERE UserId = @UserId;
    END
    ELSE
    BEGIN
        INSERT INTO Badges (UserId, Bronze, Silver, Gold)
        VALUES (@UserId, @Bronze, @Silver, @Gold);
    END
END;


------------------- Index ---------------------
-- For searching by recipe name
CREATE NONCLUSTERED INDEX idx_RecipeName ON Recipes(RecipeName);
CREATE NONCLUSTERED INDEX IX_Recipes_CategoryId ON Recipes (CategoryId);

------------------- view ---------------------
CREATE VIEW RecipeDetails AS
SELECT 
    r.RecipeId, 
    r.RecipeName, 
    r.Ingredients,
    c.CategoryId,
    c.CategoryName, 
    u.Username, 
    u.Skills
FROM Recipes r
JOIN Users u ON r.UserId = u.Id
JOIN Category c ON r.CategoryId = c.CategoryId;

-----------my recipe page view-----------
CREATE VIEW UserRecipesView AS
SELECT 
    R.RecipeId, 
    R.RecipeName, 
    C.CategoryName, 
    R.DateCreated, 
    R.UserId
FROM 
    Recipes R
INNER JOIN 
    Category C ON R.CategoryId = C.CategoryId;


-------- user profile page view -----------------
CREATE VIEW UserProfileView AS
SELECT 
    u.Id AS UserId,
    u.username,
    u.fullname,
    u.skills,
    u.Points,
    b.Bronze,
    b.Silver,
    b.Gold
FROM 
    Users u
INNER JOIN 
    Badges b ON u.Id = b.UserId;

----------- favourite page------------
CREATE VIEW UserFavouriteRecipesView AS
SELECT 
    F.UserId,
    R.RecipeId,
    R.RecipeName,
    R.Ingredients,
    R.StepsToCook
FROM 
    Favourites F
INNER JOIN 
    Recipes R ON F.RecipeId = R.RecipeId;


-------------------- Trigger for delete recipe from fav and recipe table -------------------
CREATE TRIGGER DeleteRecipeFavandPoints
ON Recipes
INSTEAD OF DELETE
AS
BEGIN
    -- First delete from Favourites
    DELETE FROM Favourites
    WHERE RecipeId IN (SELECT RecipeId FROM DELETED);

    -- Then deduct points
    UPDATE Users
    SET Points = CASE 
        WHEN Points >= 10 THEN Points - 10
        ELSE Points
    END
    WHERE Id IN (SELECT UserId FROM DELETED);

    -- Finally delete from Recipes
    DELETE FROM Recipes
    WHERE RecipeId IN (SELECT RecipeId FROM DELETED);
END;


------------------------- Trigger for user log ----------------------------------
CREATE TRIGGER trg_LogUserUpdates
ON Users
AFTER UPDATE
AS
BEGIN
    -- Only log relevant columns
    IF UPDATE(username) OR UPDATE(fullname) OR UPDATE(email) OR UPDATE(password)
    BEGIN
        INSERT INTO UserUpdateLog (UserId, UpdatedColumn, OldValue, NewValue)
        SELECT 
            inserted.Id,
            CASE 
                WHEN inserted.username <> deleted.username THEN 'username'
                WHEN inserted.fullname <> deleted.fullname THEN 'fullname'
                WHEN inserted.email <> deleted.email THEN 'email'
                WHEN inserted.password <> deleted.password THEN 'password'
            END,
            CASE 
                WHEN inserted.username <> deleted.username THEN deleted.username
                WHEN inserted.fullname <> deleted.fullname THEN deleted.fullname
                WHEN inserted.email <> deleted.email THEN deleted.email
                WHEN inserted.password <> deleted.password THEN deleted.password
            END,
            CASE 
                WHEN inserted.username <> deleted.username THEN inserted.username
                WHEN inserted.fullname <> deleted.fullname THEN inserted.fullname
                WHEN inserted.email <> deleted.email THEN inserted.email
                WHEN inserted.password <> deleted.password THEN inserted.password
            END
        FROM inserted
        JOIN deleted ON inserted.Id = deleted.Id;
    END
END;
